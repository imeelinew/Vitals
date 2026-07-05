import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let collector = MetricsCollector()
    private var panel: StatusPanelView?
    private var appListView: AppListView?
    private var panelMenuItem: NSMenuItem?
    private var appListItem: NSMenuItem?
    private var launchAtLoginItem: NSMenuItem?

    private let titleAttr = NSMutableAttributedString()
    private let titleFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private var lastTitleKey: String = ""

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
        let cpuText = collector.hasCPUSample ? "\(Int(collector.cpuUsage.rounded()))%" : "--%"
        let memText = "\(Int(collector.memoryUsage.rounded()))%"
        let pressureKey = collector.pressure.rawValue

        let key = "cpu=\(cpuText)|mem=\(memText)|p=\(pressureKey)|enabled=\(MenuBarPrefs.isEnabled(.cpu))\(MenuBarPrefs.isEnabled(.memory))\(MenuBarPrefs.isEnabled(.pressure))"
        if key == lastTitleKey { return }
        lastTitleKey = key

        titleAttr.beginEditing()
        titleAttr.deleteCharacters(in: NSRange(location: 0, length: titleAttr.length))

        var first = true
        for item in MenuBarItem.allCases where MenuBarPrefs.isEnabled(item) {
            if !first { appendTitle(" · ") }
            first = false
            switch item {
            case .cpu:
                appendTitle("CPU \(cpuText)")
            case .memory:
                appendTitle("MEM \(memText)")
            case .pressure:
                appendTitle("●", color: collector.pressure.color)
            }
        }

        titleAttr.endEditing()

        if titleAttr.length == 0 {
            statusItem.button?.title = ""
        } else {
            statusItem.button?.attributedTitle = titleAttr
        }
    }

    private func appendTitle(_ text: String, color: NSColor = .labelColor) {
        titleAttr.append(NSAttributedString(string: text, attributes: [
            .font: titleFont,
            .foregroundColor: color
        ]))
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let panelItem = NSMenuItem()
        menu.addItem(panelItem)
        self.panelMenuItem = panelItem

        menu.addItem(.separator())

        let appListItem = NSMenuItem()
        menu.addItem(appListItem)
        self.appListItem = appListItem

        menu.addItem(.separator())

        for item in MenuBarItem.allCases {
            let mi = NSMenuItem(title: item.label, action: #selector(toggleItem(_:)), keyEquivalent: "")
            mi.target = self
            mi.state = MenuBarPrefs.isEnabled(item) ? .on : .off
            mi.representedObject = item.rawValue
            menu.addItem(mi)
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
        lastTitleKey = ""
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

        if panel == nil, let pmItem = panelMenuItem {
            let p = StatusPanelView(collector: collector)
            pmItem.view = p
            self.panel = p
        }
        panel?.refresh()

        if appListView == nil, let alItem = appListItem {
            let alv = AppListView()
            alItem.view = alv
            self.appListView = alv
        }
        appListView?.refresh()

        launchAtLoginItem?.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    func menuDidClose(_ menu: NSMenu) {
        panelMenuItem?.view = nil
        appListItem?.view = nil
        panel = nil
        appListView = nil
    }
}
