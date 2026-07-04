import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let collector = MetricsCollector()
    private var panel: StatusPanelView?
    private var settingsController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "CPU --% · MEM --%"

        collector.onUpdate = { [weak self] in
            self?.refreshUI()
        }
        collector.start()
        buildMenu()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: AppSettings.didChangeNotification,
            object: nil
        )
    }

    private func refreshUI() {
        renderTitle()
        panel?.refresh()
    }

    private func renderTitle() {
        let enabled = AppSettings.shared.enabledDisplayItems
        let cpu = collector.cpuUsage
        let mem = collector.memoryUsage
        let pressure = collector.pressure

        let attr = NSMutableAttributedString()
        let baseFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let baseColor = NSColor.labelColor

        func append(_ text: String, color: NSColor = baseColor) {
            attr.append(NSAttributedString(string: text, attributes: [
                .font: baseFont,
                .foregroundColor: color
            ]))
        }

        let order: [DisplayItem] = [.cpu, .memory, .pressure]
        var first = true
        for item in order where enabled.contains(item) {
            if !first { append(" · ") }
            first = false
            switch item {
            case .cpu:
                let cpuText = collector.hasCPUSample ? "\(Int(cpu.rounded()))%" : "--%"
                append("CPU \(cpuText)")
            case .memory:
                append("MEM \(Int(mem.rounded()))%")
            case .pressure:
                let color: NSColor
                switch pressure {
                case .normal: color = .systemGreen
                case .warning: color = .systemYellow
                case .critical: color = .systemRed
                }
                append("●", color: color)
            }
        }

        if attr.length == 0 {
            append("MenubarStatus")
        }

        statusItem.button?.attributedTitle = attr
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let panelItem = NSMenuItem()
        let p = StatusPanelView(collector: collector)
        panelItem.view = p
        self.panel = p
        menu.addItem(panelItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "退出 MenubarStatus", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func settingsChanged() {
        renderTitle()
    }

    @objc private func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController()
        }
        settingsController?.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        collector.sampleOnce()
    }
}
