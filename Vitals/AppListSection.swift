import AppKit
import Darwin

struct RunningAppInfo {
    let app: NSRunningApplication
    let memoryBytes: UInt64

    var displayName: String {
        app.localizedName ?? app.bundleIdentifier ?? "PID \(app.processIdentifier)"
    }

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
        let ownPid = ProcessInfo.processInfo.processIdentifier
        let grouped = groupedMemoryBytes()
        var infos: [RunningAppInfo] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular, app.processIdentifier != ownPid else { continue }
            let bundlePath = app.bundleURL?.path ?? ""
            let bytes = grouped[bundlePath] ?? memoryBytes(for: app.processIdentifier)
            infos.append(RunningAppInfo(app: app, memoryBytes: bytes))
        }
        infos.sort { $0.memoryBytes > $1.memoryBytes }
        return infos
    }

    private static func groupedMemoryBytes() -> [String: UInt64] {
        let bufferCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        let count = Int(bufferCount) / MemoryLayout<pid_t>.size
        var pids = [pid_t](repeating: 0, count: count)
        let actual = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, bufferCount)
        let actualCount = Int(actual) / MemoryLayout<pid_t>.size

        var groups: [String: UInt64] = [:]
        for pid in pids.prefix(actualCount) {
            var path = [CChar](repeating: 0, count: 4096)
            let len = proc_pidpath(pid, &path, 4096)
            guard len > 0 else { continue }
            let p = String(cString: path)
            guard let r = p.range(of: ".app/") else { continue }
            let bundle = String(p[..<r.lowerBound]) + ".app"
            let bytes = memoryBytes(for: pid)
            groups[bundle, default: 0] += bytes
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

final class AppListView: NSView {
    private struct Row {
        let checkbox: NSButton
        let memLabel: NSTextField
        let info: RunningAppInfo
    }

    private var rows: [Row] = []
    private let quitButton = NSButton()
    private let titleLabel = NSTextField(labelWithString: "运行中的应用")
    private let emptyLabel = NSTextField(labelWithString: "（无其他应用）")

    private let margin: CGFloat = 12
    private let contentWidth: CGFloat = 196
    private let rowHeight: CGFloat = 18
    private let rowSpacing: CGFloat = 2
    private let memLabelWidth: CGFloat = 56
    private let titleH: CGFloat = 16
    private let titleY: CGFloat = 8

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
            row.memLabel.removeFromSuperview()
        }
        rows = []
        quitButton.isEnabled = false
        quitButton.title = "退出选中的应用"
    }

    func refresh() {
        clearRows()

        let apps = AppListSection.collectAll()

        if apps.isEmpty {
            emptyLabel.isHidden = false
            quitButton.isHidden = true
            layoutFrames(rowCount: 0)
            return
        }
        emptyLabel.isHidden = true
        quitButton.isHidden = false

        let cbWidth = contentWidth - memLabelWidth - 6
        let memX = margin + contentWidth - memLabelWidth
        let listY = titleY + titleH + 6

        for (i, info) in apps.enumerated() {
            let cb = NSButton(checkboxWithTitle: info.displayName, target: self, action: #selector(checkboxToggled(_:)))
            cb.font = .systemFont(ofSize: 12)
            cb.lineBreakMode = .byTruncatingTail

            let memLabel = NSTextField(labelWithString: info.memoryText)
            memLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            memLabel.alignment = .right
            memLabel.textColor = .secondaryLabelColor

            let y = listY + CGFloat(i) * (rowHeight + rowSpacing)
            cb.frame = NSRect(x: margin, y: y, width: cbWidth, height: rowHeight)
            memLabel.frame = NSRect(x: memX, y: y, width: memLabelWidth, height: rowHeight)

            addSubview(cb)
            addSubview(memLabel)
            rows.append(Row(checkbox: cb, memLabel: memLabel, info: info))
        }

        layoutFrames(rowCount: apps.count)
        updateQuitButton()
    }

    private func layoutFrames(rowCount: Int) {
        let listY = titleY + titleH + 6
        let listH = CGFloat(rowCount) * (rowHeight + rowSpacing) - (rowCount > 0 ? rowSpacing : 0)
        let quitY = listY + listH + 10
        let quitH: CGFloat = 22
        let totalH = quitY + quitH + 10

        self.frame = NSRect(x: 0, y: 0, width: margin * 2 + contentWidth, height: totalH)

        titleLabel.frame = NSRect(x: margin, y: titleY, width: contentWidth, height: titleH)
        emptyLabel.frame = NSRect(x: margin, y: listY, width: contentWidth, height: rowHeight)
        quitButton.frame = NSRect(x: margin, y: quitY, width: contentWidth, height: quitH)
    }

    @objc private func checkboxToggled(_ sender: NSButton) {
        updateQuitButton()
    }

    private func updateQuitButton() {
        let count = rows.filter { $0.checkbox.state == .on }.count
        if count > 0 {
            quitButton.title = "退出选中的 \(count) 个应用"
            quitButton.isEnabled = true
        } else {
            quitButton.title = "退出选中的应用"
            quitButton.isEnabled = false
        }
    }

    @objc private func quitSelected() {
        let toQuit = rows.filter { $0.checkbox.state == .on }.map { $0.info.app }
        for app in toQuit {
            app.terminate()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refresh()
        }
    }
}
