import AppKit
import Darwin

struct RunningAppInfo {
    let pid: pid_t
    let name: String
    let memoryBytes: UInt64

    var memoryText: String {
        let mb = Double(memoryBytes) / 1_048_576
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
    }
}

enum AppListSection {
    static func collectAll() -> [RunningAppInfo] {
        autoreleasepool {
            let ownPid = ProcessInfo.processInfo.processIdentifier
            let grouped = groupedMemoryBytes()

            var infos: [RunningAppInfo] = []
            infos.reserveCapacity(grouped.count)

            for app in NSWorkspace.shared.runningApplications {
                guard app.activationPolicy == .regular, app.processIdentifier != ownPid else { continue }
                let bundlePath = app.bundleURL?.path ?? ""
                let bytes = grouped[bundlePath] ?? memoryBytes(for: app.processIdentifier)
                let name = app.localizedName ?? app.bundleIdentifier ?? "PID \(app.processIdentifier)"
                infos.append(RunningAppInfo(pid: app.processIdentifier, name: name, memoryBytes: bytes))
            }
            infos.sort { $0.memoryBytes > $1.memoryBytes }
            return infos
        }
    }

    private static func groupedMemoryBytes() -> [String: UInt64] {
        let bufferCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        let count = Int(bufferCount) / MemoryLayout<pid_t>.size
        var pids = [pid_t](repeating: 0, count: count)
        let actual = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, bufferCount)
        let actualCount = Int(actual) / MemoryLayout<pid_t>.size

        var pathBuffer = [CChar](repeating: 0, count: 1024)
        var groups: [String: UInt64] = [:]
        for pid in pids.prefix(actualCount) {
            let len = proc_pidpath(pid, &pathBuffer, 1024)
            guard len > 0 else { continue }
            let p = String(cString: pathBuffer)
            guard let r = p.range(of: ".app/") else { continue }
            let bundle = String(p[..<r.lowerBound]) + ".app"
            groups[bundle, default: 0] += memoryBytes(for: pid)
        }
        return groups
    }

    private static func memoryBytes(for pid: pid_t) -> UInt64 {
        physicalFootprintBytes(for: pid) ?? residentBytes(for: pid)
    }

    private static func physicalFootprintBytes(for pid: pid_t) -> UInt64? {
        var info = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_V2, rebound)
            }
        }
        guard result == 0 else { return nil }
        return info.ri_phys_footprint
    }

    private static func residentBytes(for pid: pid_t) -> UInt64 {
        var info = proc_taskinfo()
        let size = proc_pidinfo(
            pid,
            PROC_PIDTASKINFO,
            0,
            &info,
            Int32(MemoryLayout<proc_taskinfo>.size)
        )
        guard size == Int32(MemoryLayout<proc_taskinfo>.size) else { return 0 }
        return info.pti_resident_size
    }
}

enum SafeAppPrefs {
    private static let key = "appList.safeAppBundleIDs"
    private static let defaults = UserDefaults.standard

    static func bundleIDs() -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    static func setBundleIDs(_ ids: Set<String>) {
        defaults.set(Array(ids).sorted(), forKey: key)
    }
}

private enum AppProcessTerminator {
    private static let pathBufferSize: Int32 = 4_096

    static func forceQuit(pid: pid_t) {
        autoreleasepool {
            guard let app = NSRunningApplication(processIdentifier: pid) else { return }
            let bundlePath = app.bundleURL.map(canonicalPath)
            var relatedPIDs = bundlePath.map(processesInsideBundle) ?? []
            relatedPIDs.insert(pid)

            _ = app.forceTerminate()

            guard let bundlePath else { return }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.75) {
                autoreleasepool {
                    killRemaining(relatedPIDs, insideBundle: bundlePath)
                }
            }
        }
    }

    private static func processesInsideBundle(_ bundlePath: String) -> Set<pid_t> {
        let bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bufferSize > 0 else { return [] }

        let count = Int(bufferSize) / MemoryLayout<pid_t>.size
        var pids = [pid_t](repeating: 0, count: count)
        let actualSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, bufferSize)
        let actualCount = Int(actualSize) / MemoryLayout<pid_t>.size

        var matches = Set<pid_t>()
        for pid in pids.prefix(actualCount) where pid > 0 {
            if executablePath(for: pid).map({ isInsideBundle($0, bundlePath: bundlePath) }) == true {
                matches.insert(pid)
            }
        }
        return matches
    }

    private static func killRemaining(_ pids: Set<pid_t>, insideBundle bundlePath: String) {
        for pid in pids where pid > 0 {
            guard let path = executablePath(for: pid), isInsideBundle(path, bundlePath: bundlePath) else {
                continue
            }
            _ = Darwin.kill(pid, SIGKILL)
        }
    }

    private static func executablePath(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(pathBufferSize))
        guard proc_pidpath(pid, &buffer, UInt32(pathBufferSize)) > 0 else { return nil }
        return canonicalPath(URL(fileURLWithPath: String(cString: buffer)))
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func isInsideBundle(_ executablePath: String, bundlePath: String) -> Bool {
        executablePath.hasPrefix(bundlePath + "/")
    }
}

final class AppListView: NSView {
    private struct Row {
        let frame: NSRect
        let pid: pid_t
        let name: String
        let memoryText: String
        let bundleIdentifier: String?
        let isSafe: Bool
        var isSelected: Bool
    }

    private struct SectionHeader {
        let title: String
        let frame: NSRect
    }

    private var rows: [Row] = []
    private var sectionHeaders: [SectionHeader] = []
    private var anchorIdx: Int?
    private var dragStartIdx: Int?
    private var dragLastIdx: Int?
    private var dragStartPoint: NSPoint?
    private var dragDidMove = false
    private var dragStartSelected = false
    private var safeButtonFrame = NSRect.zero
    private var quitButtonFrame = NSRect.zero

    private let margin: CGFloat = 12
    private let contentWidth: CGFloat = 196
    private let rowHeight: CGFloat = 18
    private let rowSpacing: CGFloat = 2
    private let sectionSpacing: CGFloat = 8
    private let sectionHeaderHeight: CGFloat = 15
    private let memLabelWidth: CGFloat = 56
    private let titleHeight: CGFloat = 16
    private let titleY: CGFloat = 8
    private let checkboxSize: CGFloat = 12
    private let buttonHeight: CGFloat = 22

    private let titleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
        .foregroundColor: NSColor.labelColor
    ]
    private let nameAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12),
        .foregroundColor: NSColor.labelColor
    ]
    private let memoryAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor.secondaryLabelColor
    ]
    private let secondaryAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11, weight: .medium),
        .foregroundColor: NSColor.tertiaryLabelColor
    ]
    private let buttonAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11),
        .foregroundColor: NSColor.labelColor
    ]
    private let disabledButtonAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11),
        .foregroundColor: NSColor.disabledControlTextColor
    ]

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 60))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refresh() {
        autoreleasepool {
            rebuildRows(from: AppListSection.collectAll())
        }
        needsDisplay = true
    }

    private func rebuildRows(from apps: [RunningAppInfo]) {
        rows.removeAll(keepingCapacity: true)
        sectionHeaders.removeAll(keepingCapacity: true)
        anchorIdx = nil
        dragStartIdx = nil
        dragLastIdx = nil
        dragStartPoint = nil
        dragDidMove = false

        let safeIDs = SafeAppPrefs.bundleIDs()
        var normal: [(RunningAppInfo, String?)] = []
        var safe: [(RunningAppInfo, String?)] = []
        normal.reserveCapacity(apps.count)
        safe.reserveCapacity(safeIDs.count)

        for info in apps {
            let bundleID = NSRunningApplication(processIdentifier: info.pid)?.bundleIdentifier
            if let bundleID, safeIDs.contains(bundleID) {
                safe.append((info, bundleID))
            } else {
                normal.append((info, bundleID))
            }
        }

        var y = titleY + titleHeight + 6
        appendRows(normal, isSafe: false, y: &y)

        if !safe.isEmpty {
            if !normal.isEmpty { y += sectionSpacing - rowSpacing }
            sectionHeaders.append(SectionHeader(
                title: "安全区",
                frame: NSRect(x: margin, y: y, width: contentWidth, height: sectionHeaderHeight)
            ))
            y += sectionHeaderHeight + 4
            appendRows(safe, isSafe: true, y: &y)
        }

        let contentBottom = apps.isEmpty ? y + rowHeight : y - rowSpacing
        let safeY = contentBottom + 10
        safeButtonFrame = apps.isEmpty ? .zero : NSRect(x: margin, y: safeY, width: contentWidth, height: buttonHeight)
        let quitY = apps.isEmpty ? safeY : safeY + buttonHeight + 6
        quitButtonFrame = apps.isEmpty ? .zero : NSRect(x: margin, y: quitY, width: contentWidth, height: buttonHeight)
        let totalHeight = apps.isEmpty ? contentBottom + 10 : quitY + buttonHeight + 10
        frame = NSRect(x: 0, y: 0, width: margin * 2 + contentWidth, height: totalHeight)
    }

    private func appendRows(_ infos: [(RunningAppInfo, String?)], isSafe: Bool, y: inout CGFloat) {
        for (info, bundleID) in infos {
            rows.append(Row(
                frame: NSRect(x: margin, y: y, width: contentWidth, height: rowHeight),
                pid: info.pid,
                name: info.name,
                memoryText: info.memoryText,
                bundleIdentifier: bundleID,
                isSafe: isSafe,
                isSelected: false
            ))
            y += rowHeight + rowSpacing
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        ("运行中的应用" as NSString).draw(
            in: NSRect(x: margin, y: titleY, width: contentWidth, height: titleHeight),
            withAttributes: titleAttributes
        )

        if rows.isEmpty {
            ("（无其他应用）" as NSString).draw(
                in: NSRect(x: margin, y: titleY + titleHeight + 6, width: contentWidth, height: rowHeight),
                withAttributes: secondaryAttributes
            )
            return
        }

        for header in sectionHeaders {
            (header.title as NSString).draw(in: header.frame, withAttributes: secondaryAttributes)
            NSColor.separatorColor.setFill()
            NSRect(x: margin + 48, y: header.frame.midY, width: contentWidth - 48, height: 1).fill()
        }

        for row in rows where dirtyRect.intersects(row.frame) {
            drawRow(row)
        }

        var selectedCount = 0
        var safeEligibleCount = 0
        var allEligibleSafe = true
        var allEligibleUnsafe = true
        for row in rows where row.isSelected {
            selectedCount += 1
            guard row.bundleIdentifier != nil else { continue }
            safeEligibleCount += 1
            allEligibleSafe = allEligibleSafe && row.isSafe
            allEligibleUnsafe = allEligibleUnsafe && !row.isSafe
        }
        let safeTitle: String
        if safeEligibleCount == 0 {
            safeTitle = "安全区"
        } else if allEligibleSafe {
            safeTitle = "移出安全区"
        } else if allEligibleUnsafe {
            safeTitle = "移入安全区"
        } else {
            safeTitle = "切换安全区"
        }
        drawButton(title: safeTitle, frame: safeButtonFrame, enabled: safeEligibleCount > 0)
        let quitTitle = selectedCount == 0 ? "强制退出选中的应用" : "强制退出选中的 \(selectedCount) 个应用"
        drawButton(title: quitTitle, frame: quitButtonFrame, enabled: selectedCount > 0)
    }

    private func drawRow(_ row: Row) {
        let checkboxRect = NSRect(
            x: row.frame.minX + 1,
            y: row.frame.midY - checkboxSize / 2,
            width: checkboxSize,
            height: checkboxSize
        )
        let checkbox = NSBezierPath(roundedRect: checkboxRect, xRadius: 2.5, yRadius: 2.5)
        if row.isSelected {
            NSColor.controlAccentColor.setFill()
            checkbox.fill()
            NSColor.white.setStroke()
            let tick = NSBezierPath()
            tick.lineWidth = 1.5
            tick.move(to: NSPoint(x: checkboxRect.minX + 2.5, y: checkboxRect.midY))
            tick.line(to: NSPoint(x: checkboxRect.minX + 5, y: checkboxRect.maxY - 2.5))
            tick.line(to: NSPoint(x: checkboxRect.maxX - 2, y: checkboxRect.minY + 2.5))
            tick.stroke()
        } else {
            NSColor.separatorColor.setStroke()
            checkbox.lineWidth = 1
            checkbox.stroke()
        }

        let nameX = checkboxRect.maxX + 6
        let memoryX = row.frame.maxX - memLabelWidth
        (row.name as NSString).draw(
            in: NSRect(x: nameX, y: row.frame.minY + 1, width: memoryX - nameX - 5, height: rowHeight),
            withAttributes: nameAttributes
        )
        let memorySize = (row.memoryText as NSString).size(withAttributes: memoryAttributes)
        (row.memoryText as NSString).draw(
            at: NSPoint(x: row.frame.maxX - memorySize.width, y: row.frame.minY + 2),
            withAttributes: memoryAttributes
        )
    }

    private func drawButton(title: String, frame: NSRect, enabled: Bool) {
        let path = NSBezierPath(roundedRect: frame, xRadius: 5, yRadius: 5)
        (enabled ? NSColor.controlColor : NSColor.controlColor.withAlphaComponent(0.45)).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        let attributes = enabled ? buttonAttributes : disabledButtonAttributes
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(
            at: NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control), toggleSafeZone(at: event.locationInWindow) {
            return
        }

        dragStartPoint = convert(event.locationInWindow, from: nil)
        dragStartIdx = rowIndex(at: event.locationInWindow)
        dragLastIdx = dragStartIdx
        dragDidMove = false
        if let start = dragStartIdx {
            dragStartSelected = rows[start].isSelected
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartIdx, let startPoint = dragStartPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        let dx = point.x - startPoint.x
        let dy = point.y - startPoint.y
        if !dragDidMove, sqrt(dx * dx + dy * dy) < 3 { return }
        dragDidMove = true
        guard let current = rowIndex(at: event.locationInWindow), current != dragLastIdx else { return }
        let target = !dragStartSelected
        for index in min(start, current)...max(start, current) {
            rows[index].isSelected = target
        }
        dragLastIdx = current
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStartIdx = nil
            dragLastIdx = nil
            dragStartPoint = nil
            dragDidMove = false
        }

        let point = convert(event.locationInWindow, from: nil)
        if safeButtonFrame.contains(point), canToggleSelectedSafeZone {
            toggleSelectedSafeZone()
            return
        }
        if quitButtonFrame.contains(point), rows.contains(where: \.isSelected) {
            quitSelected()
            return
        }

        guard let start = dragStartIdx, !dragDidMove else { return }
        if event.modifierFlags.contains(.shift), let anchor = anchorIdx {
            let target = !rows[start].isSelected
            for index in min(anchor, start)...max(anchor, start) {
                rows[index].isSelected = target
            }
        } else {
            rows[start].isSelected.toggle()
            anchorIdx = start
        }
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        if toggleSafeZone(at: event.locationInWindow) { return }
        super.rightMouseDown(with: event)
    }

    private func rowIndex(at location: NSPoint) -> Int? {
        let point = convert(location, from: nil)
        return rows.firstIndex { $0.frame.contains(point) }
    }

    private func toggleSafeZone(at location: NSPoint) -> Bool {
        guard let index = rowIndex(at: location), let bundleID = rows[index].bundleIdentifier else { return false }
        var ids = SafeAppPrefs.bundleIDs()
        if rows[index].isSafe {
            ids.remove(bundleID)
        } else {
            ids.insert(bundleID)
        }
        SafeAppPrefs.setBundleIDs(ids)
        refresh()
        return true
    }

    private var canToggleSelectedSafeZone: Bool {
        rows.contains { $0.isSelected && $0.bundleIdentifier != nil }
    }

    private func quitSelected() {
        let pids = rows.lazy.filter(\.isSelected).map(\.pid)
        for pid in pids {
            AppProcessTerminator.forceQuit(pid: pid)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refresh()
        }
    }

    private func toggleSelectedSafeZone() {
        let selected = rows.filter { $0.isSelected && $0.bundleIdentifier != nil }
        guard !selected.isEmpty else { return }

        var ids = SafeAppPrefs.bundleIDs()
        if selected.allSatisfy(\.isSafe) {
            for row in selected {
                if let bundleID = row.bundleIdentifier { ids.remove(bundleID) }
            }
        } else if selected.allSatisfy({ !$0.isSafe }) {
            for row in selected {
                if let bundleID = row.bundleIdentifier { ids.insert(bundleID) }
            }
        } else {
            for row in selected {
                guard let bundleID = row.bundleIdentifier else { continue }
                if row.isSafe { ids.remove(bundleID) } else { ids.insert(bundleID) }
            }
        }
        SafeAppPrefs.setBundleIDs(ids)
        refresh()
    }
}
