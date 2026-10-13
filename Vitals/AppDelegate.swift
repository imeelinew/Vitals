import AppKit
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let instanceLockPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/com.eli.Vitals/instance.lock")

    private var instanceLockFD: Int32 = -1
    private var statusItem: NSStatusItem!
    private let windowManagement = WindowManagementService()
    private let collector = MetricsCollector()
    private let updateService = UpdateService()
    private let panelMenuItem = NSMenuItem()
    private let appListItem = NSMenuItem()
    private var launchAtLoginItem: NSMenuItem?
    private var checkForUpdatesItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard acquireInstanceLock() else {
            NSApp.terminate(nil)
            return
        }

        ensureInitialLaunchAtLogin()
        migrateLaunchAtLoginIfNeeded()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let symbol = NSImage(systemSymbolName: "gauge.with.needle", accessibilityDescription: "Vitals")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .medium))
        symbol?.isTemplate = true
        statusItem.button?.image = symbol
        statusItem.button?.imagePosition = .imageOnly

        collector.onUpdate = { [weak self] in
            self?.panelMenuItem.view?.needsDisplay = true
        }
        windowManagement.start()
        collector.start()
        buildMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowManagement.stop()
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

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        menu.addItem(panelMenuItem)
        menu.addItem(.separator())
        menu.addItem(appListItem)

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

        panelMenuItem.view = panelMenuItem.view ?? StatusPanelView(collector: collector)
        panelMenuItem.view?.needsDisplay = true

        let appList = appListItem.view as? AppListView ?? AppListView()
        appListItem.view = appList
        appList.refresh()

        launchAtLoginItem?.state = LaunchAtLogin.isEnabled ? .on : .off
        checkForUpdatesItem?.isEnabled = updateService.canCheckForUpdates
    }

    func menuDidClose(_ menu: NSMenu) {
        panelMenuItem.view = nil
        appListItem.view = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            malloc_zone_pressure_relief(nil, 0)
        }
    }
}
