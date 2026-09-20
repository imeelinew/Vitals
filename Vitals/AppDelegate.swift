import AppKit
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let instanceLockPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/com.eli.Vitals/instance.lock")

    private var instanceLockFD: Int32 = -1
    private var statusItem: NSStatusItem!
    private let collector = MetricsCollector()
    private let updateService = UpdateService()
    private var panel: StatusPanelView?
    private var appListView: AppListView?
    private var panelMenuItem: NSMenuItem?
    private var appListItem: NSMenuItem?
    private var launchAtLoginItem: NSMenuItem?
    private var checkForUpdatesItem: NSMenuItem?

    private let titleAttr = NSMutableAttributedString()
    private let titleFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private let emptySelectionImage: NSImage? = {
        guard let baseSymbol = NSImage(
            systemSymbolName: "gauge.with.needle",
            accessibilityDescription: "Vitals"
        ) else { return nil }

        let configuration = NSImage.SymbolConfiguration(
            pointSize: baseSymbol.size.height,
            weight: .medium
        )
        let symbol = baseSymbol.withSymbolConfiguration(configuration) ?? baseSymbol
        let downwardOffset: CGFloat = 0
        let image = NSImage(size: symbol.size, flipped: false) { bounds in
            symbol.draw(in: bounds.offsetBy(dx: 0, dy: -downwardOffset))
            return true
        }
        image.isTemplate = true
        return image
    }()
    private struct TitleState: Equatable {
        let cpu: Int?
        let memory: Int
        let pressure: Int
        let enabledMask: UInt8
    }

    private var lastTitleState: TitleState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard acquireInstanceLock() else {
            NSApp.terminate(nil)
            return
        }

        MenuBarPrefs.ensureDefaults()
        ensureInitialLaunchAtLogin()
        migrateLaunchAtLoginIfNeeded()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "CPU --% · MEM --%"

        collector.onUpdate = { [weak self] in
            self?.refreshUI()
        }
        collector.start()
        buildMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard instanceLockFD >= 0 else { return }
        flock(instanceLockFD, LOCK_UN)
        close(instanceLockFD)
        instanceLockFD = -1
    }

    private func acquireInstanceLock() -> Bool {
        let lockDirectory = Self.instanceLockPath.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: lockDirectory, withIntermediateDirectories: true)
        } catch {
            print("[launch] unable to create instance-lock directory: \(error)")
            return true
        }

        let fd = open(Self.instanceLockPath.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else {
            print("[launch] unable to open instance lock: \(String(cString: strerror(errno)))")
            return true
        }

        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return false
        }

        instanceLockFD = fd
        return true
    }

    private func ensureInitialLaunchAtLogin() {
        let key = "didInitialLaunchAtLoginSetup"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: key) else { return }
        try? LaunchAtLogin.enable()
        defaults.set(true, forKey: key)
    }

    private func migrateLaunchAtLoginIfNeeded() {
        do {
            try LaunchAtLogin.migrateIfNeeded()
        } catch {
            print("[launch] unable to migrate launch-at-login state: \(error)")
        }
    }

    private func refreshUI() {
        renderTitle()
        panel?.refresh()
    }

    private func renderTitle() {
        let cpu = collector.hasCPUSample ? Int(collector.cpuUsage.rounded()) : nil
        let memory = Int(collector.memoryUsage.rounded())
        let cpuEnabled = MenuBarPrefs.isEnabled(.cpu)
        let memoryEnabled = MenuBarPrefs.isEnabled(.memory)
        let pressureEnabled = MenuBarPrefs.isEnabled(.pressure)
        let enabledMask: UInt8 = (cpuEnabled ? 1 : 0) | (memoryEnabled ? 2 : 0) | (pressureEnabled ? 4 : 0)
        let state = TitleState(
            cpu: cpuEnabled ? cpu : nil,
            memory: memoryEnabled ? memory : 0,
            pressure: pressureEnabled ? collector.pressure.rawValue : 0,
            enabledMask: enabledMask
        )
        if state == lastTitleState { return }
        lastTitleState = state

        let cpuText = cpu.map { "\($0)%" } ?? "--%"
        let memText = "\(memory)%"

        titleAttr.beginEditing()
        titleAttr.deleteCharacters(in: NSRange(location: 0, length: titleAttr.length))

        if cpuEnabled { appendTitle("CPU \(cpuText)") }
        if memoryEnabled {
            if titleAttr.length > 0 { appendTitle(" · ") }
            appendTitle("MEM \(memText)")
        }
        if pressureEnabled {
            if titleAttr.length > 0 { appendTitle(" · ") }
            appendTitle("●", color: collector.pressure.color)
        }

        titleAttr.endEditing()

        if titleAttr.length == 0 {
            statusItem.button?.title = ""
            statusItem.button?.image = emptySelectionImage
            statusItem.button?.imagePosition = .imageOnly
        } else {
            statusItem.button?.image = nil
            statusItem.button?.imagePosition = .noImage
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

        let checkItem = NSMenuItem(title: "检查更新…", action: #selector(checkForUpdates), keyEquivalent: "")
        checkItem.target = self
        menu.addItem(checkItem)
        self.checkForUpdatesItem = checkItem

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
        lastTitleState = nil
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

    @objc private func checkForUpdates() {
        updateService.checkForUpdates()
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
        checkForUpdatesItem?.isEnabled = updateService.canCheckForUpdates
    }

    func menuDidClose(_ menu: NSMenu) {
        panelMenuItem?.view = nil
        appListItem?.view = nil
        panel = nil
        appListView = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            malloc_zone_pressure_relief(nil, 0)
        }
    }
}
