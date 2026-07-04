import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let collector = MetricsCollector()
    private var launchAtLoginItem: NSMenuItem!
    private var panel: StatusPanelView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "CPU --% · MEM --%"

        collector.onTitleUpdate = { [weak self] cpu, mem in
            self?.updateTitle(cpu: cpu, mem: mem)
            self?.panel?.refresh()
        }
        collector.start()
        buildMenu()
    }

    private func updateTitle(cpu: Double, mem: Double) {
        let cpuText = cpu >= 0 ? "\(Int(cpu.rounded()))%" : "--%"
        let memText = "\(Int(mem.rounded()))%"
        statusItem.button?.title = "CPU \(cpuText) · MEM \(memText)"
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

        launchAtLoginItem = NSMenuItem(title: "开机启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(launchAtLoginItem)

        let quitItem = NSMenuItem(title: "退出 MenubarStatus", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if LaunchAtLogin.isEnabled {
                try LaunchAtLogin.disable()
                launchAtLoginItem.state = .off
            } else {
                try LaunchAtLogin.enable()
                launchAtLoginItem.state = .on
            }
        } catch {
            print("[launch] error: \(error)")
            launchAtLoginItem.state = LaunchAtLogin.isEnabled ? .on : .off
        }
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
