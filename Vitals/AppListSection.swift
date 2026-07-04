import AppKit
import Darwin

struct RunningAppInfo {
    let app: NSRunningApplication
    let residentBytes: UInt64

    var displayName: String {
        app.localizedName ?? app.bundleIdentifier ?? "PID \(app.processIdentifier)"
    }

    var memoryText: String {
        let mb = Double(residentBytes) / 1_048_576
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
    }
}

enum AppListSection {
    static func collect() -> [RunningAppInfo] {
        let ownPid = ProcessInfo.processInfo.processIdentifier
        var infos: [RunningAppInfo] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular, app.processIdentifier != ownPid else { continue }
            let bytes = residentBytes(for: app.processIdentifier)
            infos.append(RunningAppInfo(app: app, residentBytes: bytes))
        }
        infos.sort { $0.residentBytes > $1.residentBytes }
        return infos
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

        let apps = AppListSection.collect()

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
