import AppKit
import Darwin

struct RunningAppInfo {
    let pid: pid_t
    let name: String
    let bundleIdentifier: String?
    let memoryBytes: UInt64
    let icon: NSImage?

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
                let icon = downsampledIcon(for: bundlePath)
                infos.append(RunningAppInfo(
                    pid: app.processIdentifier,
                    name: name,
                    bundleIdentifier: app.bundleIdentifier,
                    memoryBytes: bytes,
                    icon: icon
                ))
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

    private static func downsampledIcon(for path: String) -> NSImage? {
        guard !path.isEmpty else { return nil }
        let source = NSWorkspace.shared.icon(forFile: path)
        guard source.isValid, source.size.width > 0, source.size.height > 0 else { return nil }
        let targetSize = NSSize(width: 16, height: 16)
        let target = NSImage(size: targetSize)
        target.lockFocus()
        if let ctx = NSGraphicsContext.current {
            ctx.imageInterpolation = .high
        }
        source.draw(in: NSRect(origin: .zero, size: targetSize),
                    from: NSRect(origin: .zero, size: source.size),
                    operation: .copy,
                    fraction: 1.0)
        target.unlockFocus()
        return target
    }
}

enum SafeAppPrefs {
    private static let key = "appList.safeAppBundleIDs"
    private static let defaults = UserDefaults.standard

    static func bundleIDs() -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    static func add(_ bundleIdentifier: String) {
        var ids = bundleIDs()
        ids.insert(bundleIdentifier)
        defaults.set(Array(ids).sorted(), forKey: key)
    }

    static func remove(_ bundleIdentifier: String) {
        var ids = bundleIDs()
        ids.remove(bundleIdentifier)
        defaults.set(Array(ids).sorted(), forKey: key)
    }
}

final class AppListView: NSView {
    private struct Row {
        let checkbox: NSButton
        let iconView: IconView
        let nameLabel: NSTextField
        let memLabel: NSTextField
        var frame: NSRect
        let pid: pid_t
        let bundleIdentifier: String?
        let isSafe: Bool
    }

    private struct SectionHeader {
        let label: NSTextField
        let line: NSBox
    }

    private var rows: [Row] = []
    private var sectionHeaders: [SectionHeader] = []
    private var anchorIdx: Int?
    private var dragStartIdx: Int?
    private var dragLastIdx: Int?
    private var dragStartPoint: NSPoint?
    private var dragDidMove = false
    private var dragStartState: NSControl.StateValue = .off
    private let safeZoneButton = NSButton()
    private let quitButton = NSButton()
    private let titleLabel = NSTextField(labelWithString: "运行中的应用")
    private let emptyLabel = NSTextField(labelWithString: "（无其他应用）")

    private let margin: CGFloat = 12
    private let contentWidth: CGFloat = 196
    private let rowHeight: CGFloat = 18
    private let rowSpacing: CGFloat = 2
    private let sectionSpacing: CGFloat = 8
    private let sectionHeaderHeight: CGFloat = 15
    private let memLabelWidth: CGFloat = 56
    private let titleH: CGFloat = 16
    private let titleY: CGFloat = 8
    private let boxOffset: CGFloat = 20
    private let iconSize: CGFloat = 16
    private let iconGap: CGFloat = 4

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 60))
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        addSubview(titleLabel)

        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.isHidden = true
        addSubview(emptyLabel)

        safeZoneButton.title = "安全区"
        safeZoneButton.bezelStyle = .rounded
        safeZoneButton.controlSize = .small
        safeZoneButton.target = self
        safeZoneButton.action = #selector(toggleSelectedSafeZone)
        safeZoneButton.isEnabled = false
        addSubview(safeZoneButton)

        quitButton.title = "退出选中的应用"
        quitButton.bezelStyle = .rounded
        quitButton.controlSize = .small
        quitButton.target = self
        quitButton.action = #selector(quitSelected)
        quitButton.isEnabled = false
        addSubview(quitButton)
    }

    func clearRows() {
        for row in rows {
            row.checkbox.removeFromSuperview()
            row.iconView.removeFromSuperview()
            row.nameLabel.removeFromSuperview()
            row.memLabel.removeFromSuperview()
        }
        for header in sectionHeaders {
            header.label.removeFromSuperview()
            header.line.removeFromSuperview()
        }
        rows = []
        sectionHeaders = []
        anchorIdx = nil
        dragStartIdx = nil
        dragLastIdx = nil
        dragStartPoint = nil
        dragDidMove = false
        dragStartState = .off
        safeZoneButton.isEnabled = false
        safeZoneButton.title = "安全区"
        quitButton.isEnabled = false
        quitButton.title = "退出选中的应用"
    }

    func refresh() {
        clearRows()

        let apps = AppListSection.collectAll()
        let safeBundleIDs = SafeAppPrefs.bundleIDs()
        let normalApps = apps.filter { info in
            guard let bundleIdentifier = info.bundleIdentifier else { return true }
            return !safeBundleIDs.contains(bundleIdentifier)
        }
        let safeApps = apps.filter { info in
            guard let bundleIdentifier = info.bundleIdentifier else { return false }
            return safeBundleIDs.contains(bundleIdentifier)
        }

        if apps.isEmpty {
            emptyLabel.isHidden = false
            safeZoneButton.isHidden = true
            quitButton.isHidden = true
            layoutFrames(rowCount: 0)
            return
        }
        emptyLabel.isHidden = true
        safeZoneButton.isHidden = false
        quitButton.isHidden = false

        let cbWidth = contentWidth - memLabelWidth - 6
        let memX = margin + contentWidth - memLabelWidth
        let iconX = margin + boxOffset
        let nameX = iconX + iconSize + iconGap
        let nameWidth = cbWidth - boxOffset - iconSize - iconGap
        var y = titleY + titleH + 6

        for info in normalApps {
            appendRow(
                info,
                isSafe: false,
                y: y,
                cbWidth: cbWidth,
                memX: memX,
                iconX: iconX,
                nameX: nameX,
                nameWidth: nameWidth
            )
            y += rowHeight + rowSpacing
        }

        if !safeApps.isEmpty {
            if !normalApps.isEmpty {
                y += sectionSpacing - rowSpacing
            }
            appendSectionHeader(title: "安全区", y: y)
            y += sectionHeaderHeight + 4

            for info in safeApps {
                appendRow(
                    info,
                    isSafe: true,
                    y: y,
                    cbWidth: cbWidth,
                    memX: memX,
                    iconX: iconX,
                    nameX: nameX,
                    nameWidth: nameWidth
                )
                y += rowHeight + rowSpacing
            }
        }

        layoutFrames(contentBottomY: y - rowSpacing)
        updateButtons()
    }

    private func appendSectionHeader(title: String, y: CGFloat) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .tertiaryLabelColor
        label.frame = NSRect(x: margin, y: y, width: 44, height: sectionHeaderHeight)

        let line = NSBox()
        line.boxType = .separator
        line.frame = NSRect(
            x: margin + 48,
            y: y + (sectionHeaderHeight - 1) / 2,
            width: contentWidth - 48,
            height: 1
        )

        addSubview(label)
        addSubview(line)
        sectionHeaders.append(SectionHeader(label: label, line: line))
    }

    private func appendRow(
        _ info: RunningAppInfo,
        isSafe: Bool,
        y: CGFloat,
        cbWidth: CGFloat,
        memX: CGFloat,
        iconX: CGFloat,
        nameX: CGFloat,
        nameWidth: CGFloat
    ) {
        let cb = DisplayCheckbox()
        cb.setButtonType(.switch)
        cb.title = ""
        cb.font = .systemFont(ofSize: 12)
        cb.isBordered = false

        let iconView = IconView()
        iconView.image = info.icon

        let nameLabel = DisplayLabel(labelWithString: info.name)
        nameLabel.font = .systemFont(ofSize: 12)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.textColor = .labelColor

        let memLabel = DisplayLabel(labelWithString: info.memoryText)
        memLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        memLabel.alignment = .right
        memLabel.textColor = .secondaryLabelColor

        let iconY = y + (rowHeight - iconSize) / 2
        cb.frame = NSRect(x: margin, y: y, width: cbWidth, height: rowHeight)
        iconView.frame = NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize)
        nameLabel.frame = NSRect(x: nameX, y: y, width: nameWidth, height: rowHeight)
        memLabel.frame = NSRect(x: memX, y: y, width: memLabelWidth, height: rowHeight)

        addSubview(cb)
        addSubview(iconView)
        addSubview(nameLabel)
        addSubview(memLabel)
        rows.append(Row(
            checkbox: cb,
            iconView: iconView,
            nameLabel: nameLabel,
            memLabel: memLabel,
            frame: NSRect(x: margin, y: y, width: contentWidth, height: rowHeight),
            pid: info.pid,
            bundleIdentifier: info.bundleIdentifier,
            isSafe: isSafe
        ))
    }

    private func layoutFrames(rowCount: Int) {
        let listY = titleY + titleH + 6
        let listH = CGFloat(rowCount) * (rowHeight + rowSpacing) - (rowCount > 0 ? rowSpacing : 0)
        layoutFrames(contentBottomY: listY + listH, showsSafeZoneButton: false)
    }

    private func layoutFrames(contentBottomY: CGFloat) {
        layoutFrames(contentBottomY: contentBottomY, showsSafeZoneButton: !rows.isEmpty)
    }

    private func layoutFrames(contentBottomY: CGFloat, showsSafeZoneButton: Bool) {
        let listY = titleY + titleH + 6
        let listH = max(rowHeight, contentBottomY - listY)
        let buttonH: CGFloat = 22
        let safeY = listY + listH + 10
        let quitY = safeY + (showsSafeZoneButton ? buttonH + 6 : 0)
        let quitH = buttonH
        let totalH = quitY + quitH + 10

        self.frame = NSRect(x: 0, y: 0, width: margin * 2 + contentWidth, height: totalH)

        titleLabel.frame = NSRect(x: margin, y: titleY, width: contentWidth, height: titleH)
        emptyLabel.frame = NSRect(x: margin, y: listY, width: contentWidth, height: rowHeight)
        safeZoneButton.frame = NSRect(x: margin, y: safeY, width: contentWidth, height: buttonH)
        safeZoneButton.isHidden = !showsSafeZoneButton
        quitButton.frame = NSRect(x: margin, y: quitY, width: contentWidth, height: quitH)
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control), toggleSafeZone(at: event.locationInWindow) {
            return
        }

        dragStartPoint = convert(event.locationInWindow, from: nil)
        dragStartIdx = rowIndex(at: event.locationInWindow)
        dragLastIdx = dragStartIdx
        dragDidMove = false
        if let start = dragStartIdx, start < rows.count {
            dragStartState = rows[start].checkbox.state
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartIdx, let startPoint = dragStartPoint else { return }
        let p = convert(event.locationInWindow, from: nil)
        let dx = p.x - startPoint.x
        let dy = p.y - startPoint.y
        if !dragDidMove, sqrt(dx * dx + dy * dy) < 3 { return }
        dragDidMove = true
        guard let current = rowIndex(at: event.locationInWindow), current < rows.count else { return }
        guard current != dragLastIdx else { return }
        let from = min(start, current)
        let to = max(start, current)
        let target: NSControl.StateValue = dragStartState == .on ? .off : .on
        for i in from...to where i < rows.count {
            rows[i].checkbox.state = target
        }
        dragLastIdx = current
        updateButtons()
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStartIdx = nil
            dragLastIdx = nil
            dragStartPoint = nil
            dragDidMove = false
        }
        guard let start = dragStartIdx, start < rows.count else { return }
        if dragDidMove { return }
        let row = rows[start]
        if event.modifierFlags.contains(.shift), let anchor = anchorIdx {
            let from = min(anchor, start)
            let to = max(anchor, start)
            let target: NSControl.StateValue = row.checkbox.state == .on ? .off : .on
            for i in from...to {
                rows[i].checkbox.state = target
            }
        } else {
            row.checkbox.state = row.checkbox.state == .on ? .off : .on
            anchorIdx = start
        }
        updateButtons()
    }

    override func rightMouseDown(with event: NSEvent) {
        if toggleSafeZone(at: event.locationInWindow) { return }
        super.rightMouseDown(with: event)
    }

    private func toggleSafeZone(at location: NSPoint) -> Bool {
        guard let idx = rowIndex(at: location), idx < rows.count else { return false }
        guard let bundleIdentifier = rows[idx].bundleIdentifier else { return false }

        if rows[idx].isSafe {
            SafeAppPrefs.remove(bundleIdentifier)
        } else {
            SafeAppPrefs.add(bundleIdentifier)
        }
        refresh()
        return true
    }

    private func rowIndex(at location: NSPoint) -> Int? {
        let p = convert(location, from: nil)
        return rows.firstIndex { $0.frame.contains(p) }
    }

    private func updateButtons() {
        let selected = rows.filter { $0.checkbox.state == .on }
        let count = selected.count
        let eligibleSafeZoneRows = selected.filter { $0.bundleIdentifier != nil }

        if eligibleSafeZoneRows.isEmpty {
            safeZoneButton.title = "安全区"
            safeZoneButton.isEnabled = false
        } else if eligibleSafeZoneRows.allSatisfy(\.isSafe) {
            safeZoneButton.title = "移出安全区"
            safeZoneButton.isEnabled = true
        } else if eligibleSafeZoneRows.allSatisfy({ !$0.isSafe }) {
            safeZoneButton.title = "移入安全区"
            safeZoneButton.isEnabled = true
        } else {
            safeZoneButton.title = "切换安全区"
            safeZoneButton.isEnabled = true
        }

        if count > 0 {
            quitButton.title = "退出选中的 \(count) 个应用"
            quitButton.isEnabled = true
        } else {
            quitButton.title = "退出选中的应用"
            quitButton.isEnabled = false
        }
    }

    @objc private func quitSelected() {
        let pids = rows.filter { $0.checkbox.state == .on }.map { $0.pid }
        for pid in pids {
            if let app = NSRunningApplication(processIdentifier: pid) {
                app.terminate()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refresh()
        }
    }

    @objc private func toggleSelectedSafeZone() {
        let selected = rows.filter { $0.checkbox.state == .on && $0.bundleIdentifier != nil }
        guard !selected.isEmpty else { return }

        if selected.allSatisfy(\.isSafe) {
            for row in selected {
                if let bundleIdentifier = row.bundleIdentifier {
                    SafeAppPrefs.remove(bundleIdentifier)
                }
            }
        } else if selected.allSatisfy({ !$0.isSafe }) {
            for row in selected {
                if let bundleIdentifier = row.bundleIdentifier {
                    SafeAppPrefs.add(bundleIdentifier)
                }
            }
        } else {
            for row in selected {
                guard let bundleIdentifier = row.bundleIdentifier else { continue }
                if row.isSafe {
                    SafeAppPrefs.remove(bundleIdentifier)
                } else {
                    SafeAppPrefs.add(bundleIdentifier)
                }
            }
        }

        refresh()
    }
}

final class DisplayCheckbox: NSButton {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class DisplayLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
