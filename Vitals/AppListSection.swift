import AppKit
import ApplicationServices
import Darwin

struct RunningAppInfo {
    let pid: pid_t
    let name: String
    let bundleIdentifier: String?
    let bundleURL: URL?
    var memoryBytes: UInt64 = 0

    var memoryText: String {
        let mb = Double(memoryBytes) / 1_048_576
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
    }
}

enum AppListSection {
    static let finderBundleID = "com.apple.finder"

    // PROC_PIDCOALITIONINFO is the Darwin proc_pidinfo flavor used by XNU, but
    // its declaration lives in Apple's private proc_info header. Keep the
    // small value type local instead of importing or retaining a heavyweight API.
    private struct ProcessCoalitionInfo {
        var resourceID: UInt64 = 0
        var jetsamID: UInt64 = 0
        var reserved1: UInt64 = 0
        var reserved2: UInt64 = 0
        var reserved3: UInt64 = 0
    }

    private static let procPIDCoalitionInfo: Int32 = 20
    private static let processPathBufferSize: UInt32 = 4_096

    static func runningApplications() -> [NSRunningApplication] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
                && $0.processIdentifier != ownPID
                && $0.bundleIdentifier != finderBundleID
                && !$0.isTerminated
        }
    }

    static func collectAll() -> [RunningAppInfo] {
        autoreleasepool {
            var apps = runningApplications().map {
                RunningAppInfo(
                    pid: $0.processIdentifier,
                    name: $0.localizedName ?? $0.bundleIdentifier ?? "PID \($0.processIdentifier)",
                    bundleIdentifier: $0.bundleIdentifier,
                    bundleURL: $0.bundleURL
                )
            }
            aggregateMemory(into: &apps)
            return apps.sorted { $0.memoryBytes > $1.memoryBytes }
        }
    }

    private static func aggregateMemory(into groups: inout [RunningAppInfo]) {
        guard !groups.isEmpty else { return }

        var coalitionOwners: [UInt64: Int] = [:]
        var ambiguousCoalitions = Set<UInt64>()
        var bundleOwners: [String: Int] = [:]

        for index in groups.indices {
            if let coalitionID = resourceCoalitionID(for: groups[index].pid) {
                if coalitionOwners[coalitionID] == nil, !ambiguousCoalitions.contains(coalitionID) {
                    coalitionOwners[coalitionID] = index
                } else {
                    coalitionOwners.removeValue(forKey: coalitionID)
                    ambiguousCoalitions.insert(coalitionID)
                }
            }
            if let bundlePath = groups[index].bundleURL?.path {
                bundleOwners[bundlePath] = index
            }
        }

        let bufferCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bufferCount > 0 else {
            sampleMainProcesses(into: &groups)
            return
        }

        let count = Int(bufferCount) / MemoryLayout<pid_t>.size
        var pids = [pid_t](repeating: 0, count: count)
        let actual = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, bufferCount)
        guard actual > 0 else {
            sampleMainProcesses(into: &groups)
            return
        }

        let actualCount = Int(actual) / MemoryLayout<pid_t>.size
        var pathBuffer = [CChar](repeating: 0, count: Int(processPathBufferSize))

        for pid in pids.prefix(actualCount) where pid > 0 {
            var owner: Int?
            if let coalitionID = resourceCoalitionID(for: pid) {
                owner = coalitionOwners[coalitionID]
            }

            if owner == nil {
                let length = proc_pidpath(pid, &pathBuffer, processPathBufferSize)
                if length > 0 {
                    let path = String(cString: pathBuffer)
                    if let bundlePath = outermostBundlePath(in: path) {
                        owner = bundleOwners[bundlePath]
                    }
                }
            }

            if let owner {
                groups[owner].memoryBytes &+= memoryBytes(for: pid)
            }
        }
    }

    private static func sampleMainProcesses(into groups: inout [RunningAppInfo]) {
        for index in groups.indices {
            groups[index].memoryBytes = memoryBytes(for: groups[index].pid)
        }
    }

    private static func outermostBundlePath(in executablePath: String) -> String? {
        guard let range = executablePath.range(of: ".app/") else { return nil }
        return String(executablePath[..<range.lowerBound]) + ".app"
    }

    private static func resourceCoalitionID(for pid: pid_t) -> UInt64? {
        var info = ProcessCoalitionInfo()
        let expectedSize = Int32(MemoryLayout<ProcessCoalitionInfo>.size)
        let size = proc_pidinfo(
            pid,
            procPIDCoalitionInfo,
            0,
            &info,
            expectedSize
        )
        guard size == expectedSize, info.resourceID != 0 else { return nil }
        return info.resourceID
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

private enum AppIcon {
    static let size = NSSize(width: 16, height: 16)

    static func downsampled(for bundleURL: URL?) -> NSImage? {
        guard let path = bundleURL?.path else { return nil }
        let source = NSWorkspace.shared.icon(forFile: path)
        guard source.isValid, source.size.width > 0, source.size.height > 0 else { return nil }

        let target = NSImage(size: size)
        target.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: source.size),
            operation: .copy,
            fraction: 1
        )
        target.unlockFocus()
        return target
    }
}

private class DestructiveButton: NSButton {
    var isProminent = false

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        let fillOpacity: CGFloat = (isProminent ? 0.14 : 0.06) + (isHighlighted ? 0.04 : 0)
        let color = isEnabled ? NSColor.systemRed : NSColor.disabledControlTextColor
        color.withAlphaComponent(fillOpacity).setFill()
        path.fill()
        color.withAlphaComponent(isProminent ? 0.38 : 0.16).setStroke()
        path.lineWidth = 1
        path.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: isEnabled
                ? NSColor.systemRed.withAlphaComponent(isProminent ? 1 : 0.8)
                : NSColor.disabledControlTextColor
        ]
        let text = title as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attributes
        )
    }
}

private final class HoldDangerButton: DestructiveButton {
    private static let holdDuration: Double = 1.2
    private static let frameInterval: TimeInterval = 1.0 / 60.0
    private static let retractionDuration: Double = 0.22
    private static let initialProgress: CGFloat = 0.03
    private static let holdTitle = "长按以确认"
    private static let holdTitleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11, weight: .medium),
        .foregroundColor: NSColor.systemRed
    ]
    private static let filledTitleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11, weight: .medium),
        .foregroundColor: NSColor.white
    ]

    private var holdProgress: CGFloat = 0
    private var hasConfirmation = false
    private var retractionTimer: Timer?

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let trackingWindow = window else {
            super.mouseDown(with: event)
            return
        }

        stopRetraction()
        holdProgress = 0
        hasConfirmation = false
        setHoldProgress(Self.initialProgress)

        let startedAt = DispatchTime.now().uptimeNanoseconds
        let eventMask: NSEvent.EventTypeMask = [.leftMouseDragged, .leftMouseUp]
        var didTrigger = false
        var wasCancelled = false
        var endedByMouseUp = false

        while !endedByMouseUp {
            guard window === trackingWindow, trackingWindow.isVisible else {
                wasCancelled = true
                break
            }

            if !wasCancelled, !didTrigger {
                let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - startedAt
                let elapsed = Double(elapsedNanoseconds) / 1_000_000_000
                setHoldProgress(max(holdProgress, CGFloat(elapsed / Self.holdDuration)))

                if holdProgress >= 1 {
                    didTrigger = true
                    // Draw confirmation before requesting application termination.
                    trackingWindow.displayIfNeeded()
                    hasConfirmation = true
                    sendAction(action, to: target)
                    hasConfirmation = false
                }
            }

            let deadline = Date(timeIntervalSinceNow: Self.frameInterval)
            guard let nextEvent = trackingWindow.nextEvent(
                matching: eventMask,
                until: deadline,
                inMode: .eventTracking,
                dequeue: true
            ) else {
                continue
            }

            switch nextEvent.type {
            case .leftMouseDragged:
                let point = convert(nextEvent.locationInWindow, from: nil)
                if !bounds.contains(point) {
                    wasCancelled = true
                    resetVisualState()
                }
            case .leftMouseUp:
                endedByMouseUp = true
            default:
                break
            }
        }

        if wasCancelled {
            resetVisualState()
        } else {
            startRetraction()
        }
    }

    func consumeConfirmation() -> Bool {
        defer { hasConfirmation = false }
        return hasConfirmation
    }

    override func draw(_ dirtyRect: NSRect) {
        guard holdProgress > 0 else {
            super.draw(dirtyRect)
            return
        }

        let buttonRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: buttonRect, xRadius: 6, yRadius: 6)

        NSColor.systemRed.withAlphaComponent(0.14).setFill()
        path.fill()
        NSColor.systemRed.withAlphaComponent(0.38).setStroke()
        path.lineWidth = 1
        path.stroke()

        let progressRect = NSRect(
            x: buttonRect.minX,
            y: buttonRect.minY,
            width: buttonRect.width * holdProgress,
            height: buttonRect.height
        )
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSColor.systemRed.setFill()
        progressRect.fill()
        NSGraphicsContext.restoreGraphicsState()

        let title = Self.holdTitle as NSString
        let size = title.size(withAttributes: Self.holdTitleAttributes)
        let titlePoint = NSPoint(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2
        )
        title.draw(
            at: titlePoint,
            withAttributes: Self.holdTitleAttributes
        )

        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSBezierPath(rect: progressRect).addClip()
        title.draw(
            at: titlePoint,
            withAttributes: Self.filledTitleAttributes
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    private func setHoldProgress(_ progress: CGFloat) {
        let clamped = min(max(progress, 0), 1)
        guard clamped != holdProgress else { return }
        holdProgress = clamped
        needsDisplay = true
        displayIfNeeded()
    }

    private func startRetraction() {
        stopRetraction()
        let startingProgress = holdProgress
        guard startingProgress > 0 else {
            resetVisualState()
            return
        }

        let startedAt = DispatchTime.now().uptimeNanoseconds
        let timer = Timer(timeInterval: Self.frameInterval, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - startedAt
            let elapsed = Double(elapsedNanoseconds) / 1_000_000_000
            let fraction = min(elapsed / Self.retractionDuration, 1)
            let remaining = 1 - fraction
            self.setHoldProgress(startingProgress * CGFloat(remaining * remaining * remaining))

            if fraction >= 1 {
                self.resetVisualState()
            }
        }
        retractionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopRetraction() {
        retractionTimer?.invalidate()
        retractionTimer = nil
    }

    private func resetVisualState() {
        stopRetraction()
        holdProgress = 0
        hasConfirmation = false
        needsDisplay = true
        displayIfNeeded()
    }

    deinit {
        retractionTimer?.invalidate()
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
    static func requestQuit(pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid),
              app.bundleIdentifier != AppListSection.finderBundleID else { return }
        // A normal quit lets the application handle unsaved work or cancel quitting.
        _ = app.terminate()
    }
}

private enum RunningAppWindowCloser {
    static func requestAccessIfNeeded() -> Bool {
        guard !AXIsProcessTrusted() else { return true }
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        return false
    }

    static func closeAll(excludingBundleIDs safeIDs: Set<String>, quittingPIDs: Set<pid_t>) {
        autoreleasepool {
            closeAllRunningApplicationWindows(excludingBundleIDs: safeIDs, quittingPIDs: quittingPIDs)
        }
    }

    private static func closeAllRunningApplicationWindows(excludingBundleIDs safeIDs: Set<String>, quittingPIDs: Set<pid_t>) {
        guard AXIsProcessTrusted() else { return }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications {
            guard app.processIdentifier != ownPID, app.activationPolicy != .prohibited else { continue }
            // Leave save/cancel handling entirely to apps already asked to quit.
            guard !quittingPIDs.contains(app.processIdentifier) else { continue }
            if let bundleID = app.bundleIdentifier,
               bundleID != AppListSection.finderBundleID,
               safeIDs.contains(bundleID) { continue }
            closeWindows(of: app.processIdentifier)
        }
    }

    private static func closeWindows(of pid: pid_t) {
        let application = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXWindowsAttribute as CFString,
            &windowsValue
        ) == .success, let windows = windowsValue as? [AXUIElement] else { return }

        for window in windows {
            var closeButtonValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                window,
                kAXCloseButtonAttribute as CFString,
                &closeButtonValue
            ) == .success, let closeButtonValue else { continue }

            let closeButton = closeButtonValue as! AXUIElement
            _ = AXUIElementPerformAction(closeButton, kAXPressAction as CFString)
        }
    }
}

final class AppListView: NSView {
    private struct Row {
        var frame: NSRect
        let pid: pid_t
        let icon: NSImage?
        let name: String
        let memoryText: String
        let bundleIdentifier: String?
        let isSafe: Bool
        var isSelected: Bool
        var opacity: CGFloat = 1
    }

    private var rows: [Row] = []
    private var departingRows: [Row] = []
    private var listAnimationTimer: Timer?
    private var safeHeaderOpacity: CGFloat = 1
    private var emptyStateOpacity: CGFloat = 1
    private var safeHeaderFrame: NSRect?
    private var anchorIdx: Int?
    private var dragStartIdx: Int?
    private var dragLastIdx: Int?
    private var dragStartPoint: NSPoint?
    private var dragDidMove = false
    private var dragStartSelected = false
    private var runningAppsTimer: Timer?
    private let safeZoneButton = NSButton()
    private let quitButton = DestructiveButton()
    private let quitAllButton = HoldDangerButton()

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
    private let iconSize: CGFloat = 16
    private let iconGap: CGFloat = 4
    private let buttonHeight: CGFloat = 26
    private let clearButtonHeight: CGFloat = 32
    private let buttonGap: CGFloat = 6

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

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 60))
        configureButton(safeZoneButton, action: #selector(toggleSelectedSafeZone))
        configureButton(quitButton, action: #selector(quitSelected))
        configureButton(quitAllButton, action: #selector(quitAllButtonPressed))
        quitButton.title = "退出应用"
        quitAllButton.title = "清空工作区"
        quitAllButton.isProminent = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        runningAppsTimer?.invalidate()
        runningAppsTimer = nil
        if window == nil {
            listAnimationTimer?.invalidate()
            listAnimationTimer = nil
            departingRows.removeAll()
        }
        guard window != nil else { return }

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshIfRunningAppsChanged()
        }
        // Keep checking during menu tracking, when main-queue delays may not run.
        RunLoop.main.add(timer, forMode: .common)
        runningAppsTimer = timer
    }

    deinit {
        runningAppsTimer?.invalidate()
        listAnimationTimer?.invalidate()
    }

    private func refreshIfRunningAppsChanged() {
        let runningPIDs = Set(AppListSection.runningApplications().map(\.processIdentifier))
        guard runningPIDs != Set(rows.map(\.pid)) else { return }
        refresh()
    }

    private func configureButton(_ button: NSButton, action: Selector) {
        button.bezelStyle = .flexiblePush
        button.borderShape = .roundedRectangle
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.target = self
        button.action = action
        button.isEnabled = false
        addSubview(button)
    }

    func refresh() {
        let previousRows = rows
        let previousHeader = safeHeaderFrame
        let previousHeaderOpacity = safeHeaderOpacity
        let previousHeight = frame.height
        listAnimationTimer?.invalidate()
        listAnimationTimer = nil
        autoreleasepool {
            rebuildRows(from: AppListSection.collectAll())
        }
        let layoutChanged = previousRows.map(\.pid) != rows.map(\.pid)
            || previousHeader != safeHeaderFrame
        if layoutChanged, window?.isVisible == true,
           !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            animateListChange(from: previousRows, header: previousHeader,
                              headerOpacity: previousHeaderOpacity, height: previousHeight)
        } else {
            departingRows.removeAll()
            safeHeaderOpacity = 1
            emptyStateOpacity = 1
        }
        needsDisplay = true
    }

    private func animateListChange(from previousRows: [Row], header previousHeader: NSRect?,
                                   headerOpacity previousHeaderOpacity: CGFloat, height previousHeight: CGFloat) {
        let targets = rows
        let targetHeader = safeHeaderFrame
        let targetPIDs = Set(targets.map(\.pid))
        let starts = Dictionary(uniqueKeysWithValues: previousRows.map { ($0.pid, $0) })
        let removed = previousRows.filter { !targetPIDs.contains($0.pid) } + departingRows
        // Derive the old content edge from the view height so a removed last row
        // also animates the buttons and menu height instead of snapping them.
        let targetBottom = targets.last?.frame.maxY ?? (titleY + titleHeight + 6 + rowHeight)
        let previousBottom = previousHeight - (10 + buttonHeight + buttonGap + clearButtonHeight + 10)
        let startedAt = ProcessInfo.processInfo.systemUptime

        func render(_ progress: CGFloat, in view: AppListView) {
            view.rows = targets.map { target in
                var row = target
                if let start = starts[target.pid] {
                    row.frame.origin.y = start.frame.minY + (target.frame.minY - start.frame.minY) * progress
                    row.opacity = start.opacity + (1 - start.opacity) * progress
                } else {
                    row.frame.origin.y += 6 * (1 - progress)
                    row.opacity = progress
                }
                // Selection can change while the animation is running.
                row.isSelected = view.rows.first(where: { $0.pid == target.pid })?.isSelected ?? target.isSelected
                return row
            }
            view.departingRows = removed.map { source in
                var row = source
                row.frame.origin.x += 8 * progress
                row.opacity *= 1 - progress
                return row
            }
            if let targetHeader {
                var header = targetHeader
                if let previousHeader {
                    header.origin.y = previousHeader.minY + (targetHeader.minY - previousHeader.minY) * progress
                }
                view.safeHeaderFrame = header
                let startOpacity = previousHeader == nil ? 0 : previousHeaderOpacity
                view.safeHeaderOpacity = startOpacity + (1 - startOpacity) * progress
            } else {
                view.safeHeaderFrame = progress < 1 ? previousHeader : nil
                view.safeHeaderOpacity = previousHeaderOpacity * (1 - progress)
            }
            view.emptyStateOpacity = previousRows.isEmpty ? 1 : progress
            view.layoutButtons(contentBottom: previousBottom + (targetBottom - previousBottom) * progress)
            view.needsDisplay = true
        }

        render(0, in: self)
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            let fraction = min((ProcessInfo.processInfo.systemUptime - startedAt) / 0.24, 1)
            render(CGFloat(1 - pow(1 - fraction, 3)), in: self)
            if fraction >= 1 {
                timer.invalidate()
                self.listAnimationTimer = nil
                self.departingRows.removeAll()
            }
        }
        listAnimationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func rebuildRows(from apps: [RunningAppInfo]) {
        let selectedPIDs = Set(rows.lazy.filter(\.isSelected).map(\.pid))
        rows.removeAll(keepingCapacity: true)
        safeHeaderFrame = nil
        anchorIdx = nil
        dragStartIdx = nil
        dragLastIdx = nil
        dragStartPoint = nil
        dragDidMove = false
        let safeIDs = SafeAppPrefs.bundleIDs()
        var normal: [RunningAppInfo] = []
        var safe: [RunningAppInfo] = []
        normal.reserveCapacity(apps.count)
        safe.reserveCapacity(safeIDs.count)

        for info in apps {
            if let bundleID = info.bundleIdentifier, safeIDs.contains(bundleID) {
                safe.append(info)
            } else {
                normal.append(info)
            }
        }

        var y = titleY + titleHeight + 6
        appendRows(normal, isSafe: false, selectedPIDs: selectedPIDs, y: &y)

        if !safe.isEmpty {
            if !normal.isEmpty { y += sectionSpacing - rowSpacing }
            safeHeaderFrame = NSRect(x: margin, y: y, width: contentWidth, height: sectionHeaderHeight)
            y += sectionHeaderHeight + 4
            appendRows(safe, isSafe: true, selectedPIDs: selectedPIDs, y: &y)
        }

        updateButtons()
        layoutButtons()
    }

    private func layoutButtons(contentBottom: CGFloat? = nil) {
        let contentBottom = contentBottom ?? rows.last?.frame.maxY ?? (titleY + titleHeight + 6 + rowHeight)
        let actionY = contentBottom + 10
        let actionWidth = (contentWidth - buttonGap) / 2
        safeZoneButton.frame = NSRect(x: margin, y: actionY, width: actionWidth, height: buttonHeight)
        quitButton.frame = NSRect(x: margin + actionWidth + buttonGap, y: actionY, width: actionWidth, height: buttonHeight)
        let clearY = actionY + buttonHeight + buttonGap
        quitAllButton.frame = NSRect(x: margin, y: clearY, width: contentWidth, height: clearButtonHeight)
        setFrameSize(NSSize(width: margin * 2 + contentWidth, height: clearY + clearButtonHeight + 10))
    }

    private func appendRows(_ infos: [RunningAppInfo], isSafe: Bool, selectedPIDs: Set<pid_t>, y: inout CGFloat) {
        for info in infos {
            rows.append(Row(
                frame: NSRect(x: margin, y: y, width: contentWidth, height: rowHeight),
                pid: info.pid,
                icon: AppIcon.downsampled(for: info.bundleURL),
                name: info.name,
                memoryText: info.memoryText,
                bundleIdentifier: info.bundleIdentifier,
                isSafe: isSafe,
                isSelected: selectedPIDs.contains(info.pid)
            ))
            y += rowHeight + rowSpacing
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        ("工作区" as NSString).draw(
            in: NSRect(x: margin, y: titleY, width: contentWidth, height: titleHeight),
            withAttributes: titleAttributes
        )

        if rows.isEmpty {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.cgContext.setAlpha(emptyStateOpacity)
            ("（无其他应用）" as NSString).draw(
                in: NSRect(x: margin, y: titleY + titleHeight + 6, width: contentWidth, height: rowHeight),
                withAttributes: secondaryAttributes
            )
            NSGraphicsContext.restoreGraphicsState()
        }

        if let frame = safeHeaderFrame {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.cgContext.setAlpha(safeHeaderOpacity)
            ("安全区" as NSString).draw(in: frame, withAttributes: secondaryAttributes)
            NSColor.separatorColor.setFill()
            NSRect(x: margin + 48, y: frame.midY, width: contentWidth - 48, height: 1).fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        for row in departingRows + rows where dirtyRect.intersects(row.frame) {
            drawRow(row)
        }
    }

    private func drawRow(_ row: Row) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current?.cgContext.setAlpha(row.opacity)
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

        let iconRect = NSRect(
            x: checkboxRect.maxX + 6,
            y: row.frame.midY - iconSize / 2,
            width: iconSize,
            height: iconSize
        )
        row.icon?.draw(
            in: iconRect,
            from: NSRect(origin: .zero, size: AppIcon.size),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )

        let nameX = iconRect.maxX + iconGap
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
        updateButtons()
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStartIdx = nil
            dragLastIdx = nil
            dragStartPoint = nil
            dragDidMove = false
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
        updateButtons()
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
        SafeAppPrefs.setBundleIDs(SafeAppPrefs.bundleIDs().symmetricDifference([bundleID]))
        refresh()
        return true
    }

    private var selectedRows: [Row] { rows.filter(\.isSelected) }

    private var canQuitSelected: Bool {
        let selected = selectedRows
        return !selected.isEmpty && !selected.contains(where: \.isSafe)
    }

    private var canClearWorkspace: Bool {
        rows.contains { !$0.isSafe }
            || !NSRunningApplication.runningApplications(withBundleIdentifier: AppListSection.finderBundleID).isEmpty
    }

    private func updateButtons() {
        let eligible = selectedRows.filter { $0.bundleIdentifier != nil }
        if eligible.isEmpty {
            safeZoneButton.title = "安全区"
        } else if eligible.allSatisfy(\.isSafe) {
            safeZoneButton.title = "移出安全区"
        } else if eligible.allSatisfy({ !$0.isSafe }) {
            safeZoneButton.title = "移入安全区"
        } else {
            safeZoneButton.title = "切换安全区"
        }
        safeZoneButton.isEnabled = !eligible.isEmpty
        quitButton.isEnabled = canQuitSelected
        quitAllButton.isEnabled = canClearWorkspace
    }

    @objc private func quitSelected() {
        guard canQuitSelected else { return }
        let pids = rows.lazy.filter(\.isSelected).map(\.pid)
        for pid in pids {
            AppProcessTerminator.requestQuit(pid: pid)
        }
    }

    @objc private func quitAllButtonPressed() {
        guard quitAllButton.consumeConfirmation(),
              RunningAppWindowCloser.requestAccessIfNeeded() else { return }

        let safeIDs = SafeAppPrefs.bundleIDs()
        let pids = Set(rows.lazy.filter { !$0.isSafe }.map(\.pid))
        for pid in pids {
            AppProcessTerminator.requestQuit(pid: pid)
        }
        RunningAppWindowCloser.closeAll(excludingBundleIDs: safeIDs, quittingPIDs: pids)
    }

    @objc private func toggleSelectedSafeZone() {
        let bundleIDs = Set(selectedRows.compactMap(\.bundleIdentifier))
        SafeAppPrefs.setBundleIDs(SafeAppPrefs.bundleIDs().symmetricDifference(bundleIDs))
        refresh()
    }
}
