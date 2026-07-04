import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let collector = MetricsCollector()
    private var panel: StatusPanelView?
    private var appListView: AppListView?
    private var launchAtLoginItem: NSMenuItem?
    private var menuItemToggles: [MenuBarItem: NSMenuItem] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        MenuBarPrefs.ensureDefaults()
        ensureInitialLaunchAtLogin()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "CPU --% · MEM --%"

        collector.onUpdate = { [weak self] in
            self?.refreshUI()
        }
        collector.start()
        buildMenu()
    }

    private func ensureInitialLaunchAtLogin() {
        let key = "didInitialLaunchAtLoginSetup"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: key) else { return }
        try? LaunchAtLogin.enable()
        defaults.set(true, forKey: key)
    }

    private func refreshUI() {
        renderTitle()
        panel?.refresh()
    }

    private func renderTitle() {
        let attr = NSMutableAttributedString()
        let baseFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let baseColor = NSColor.labelColor

        func append(_ text: String, color: NSColor = baseColor) {
            attr.append(NSAttributedString(string: text, attributes: [
                .font: baseFont,
                .foregroundColor: color
            ]))
        }

        var first = true
        for item in MenuBarItem.allCases where MenuBarPrefs.isEnabled(item) {
            if !first { append(" · ") }
            first = false
            switch item {
            case .cpu:
                let cpuText = collector.hasCPUSample ? "\(Int(collector.cpuUsage.rounded()))%" : "--%"
                append("CPU \(cpuText)")
            case .memory:
                append("MEM \(Int(collector.memoryUsage.rounded()))%")
            case .pressure:
                let color: NSColor
                switch collector.pressure {
                case .normal: color = .systemGreen
                case .warning: color = .systemYellow
                case .critical: color = .systemRed
                }
                append("●", color: color)
            }
        }

        if attr.length == 0 {
            statusItem.button?.title = ""
        } else {
            statusItem.button?.attributedTitle = attr
        }
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

        let appListItem = NSMenuItem()
        let alv = AppListView()
        appListItem.view = alv
        self.appListView = alv
        menu.addItem(appListItem)

        menu.addItem(.separator())

        for item in MenuBarItem.allCases {
            let mi = NSMenuItem(title: item.label, action: #selector(toggleItem(_:)), keyEquivalent: "")
            mi.target = self
            mi.state = MenuBarPrefs.isEnabled(item) ? .on : .off
            mi.representedObject = item.rawValue
            menu.addItem(mi)
            menuItemToggles[item] = mi
        }

        menu.addItem(.separator())

        let launchItem = NSMenuItem(title: "开机自启", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(launchItem)
        self.launchAtLoginItem = launchItem

        let quitItem = NSMenuItem(title: "退出 Vitals", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func toggleItem(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let item = MenuBarItem(rawValue: raw) else { return }
        let next = sender.state != .on
        MenuBarPrefs.setEnabled(item, next)
        sender.state = next ? .on : .off
        renderTitle()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if LaunchAtLogin.isEnabled {
                try LaunchAtLogin.disable()
            } else {
                try LaunchAtLogin.enable()
            }
        } catch {
            print("[launch] error: \(error)")
        }
        launchAtLoginItem?.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        collector.sampleOnce()
        appListView?.refresh()
        launchAtLoginItem?.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    func menuDidClose(_ menu: NSMenu) {
        appListView?.clearRows()
    }
}
