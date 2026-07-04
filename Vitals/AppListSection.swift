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

    static func buildMenuItems(target: AnyObject, toggleAction: Selector, quitAction: Selector) -> [NSMenuItem] {
        let apps = collect()
        var items: [NSMenuItem] = []

        if apps.isEmpty {
            let empty = NSMenuItem(title: "（无其他应用）", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            items.append(empty)
            return items
        }

        for info in apps {
            let title = "\(info.displayName)\t\(info.memoryText)"
            let item = NSMenuItem(title: title, action: toggleAction, keyEquivalent: "")
            item.target = target
            item.state = .off
            item.representedObject = info.app
            items.append(item)
        }

        items.append(.separator())
        let quitItem = NSMenuItem(title: "退出选中的应用", action: quitAction, keyEquivalent: "")
        quitItem.target = target
        items.append(quitItem)
        return items
    }

    static func terminateSelected(_ apps: [NSRunningApplication]) {
        for app in apps {
            app.terminate()
        }
    }
}
