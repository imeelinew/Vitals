import Foundation
import ServiceManagement

enum LaunchAtLogin {
    private static let enabledKey = "launchAtLoginEnabled"
    private static let legacyAgentPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/com.eli.Vitals.plist")

    /// Avoid repeated ServiceManagement state queries in the normal 24/7
    /// process. Reconcile once during migration, then cache the user's choice.
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func enable() throws {
        let service = SMAppService.mainApp
        if service.status != .enabled {
            try service.register()
        }
        guard service.status == .enabled else { return }
        UserDefaults.standard.set(true, forKey: enabledKey)
    }

    static func disable() throws {
        let service = SMAppService.mainApp
        if service.status != .notRegistered {
            try service.unregister()
        }
        UserDefaults.standard.set(false, forKey: enabledKey)
    }

    /// Synchronizes existing installations once. Users with the old external
    /// LaunchAgent are moved to the system-managed main-app login item. The
    /// old plist is removed only after registration succeeds.
    static func migrateIfNeeded() throws {
        let defaults = UserDefaults.standard
        let hasCachedChoice = defaults.object(forKey: enabledKey) != nil
        let hasLegacyAgent = FileManager.default.fileExists(atPath: legacyAgentPath.path)
        guard !hasCachedChoice || hasLegacyAgent else { return }

        let service = SMAppService.mainApp
        if hasLegacyAgent, service.status != .enabled {
            try service.register()
        }

        let isRegistered = service.status == .enabled
        defaults.set(isRegistered, forKey: enabledKey)

        if hasLegacyAgent, isRegistered {
            try FileManager.default.removeItem(at: legacyAgentPath)
        }
    }
}
