import Foundation

enum MenuBarItem: String, CaseIterable {
    case cpu
    case memory
    case pressure

    var label: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "内存"
        case .pressure: return "内存压力"
        }
    }
}

enum MenuBarPrefs {
    private static let defaults = UserDefaults.standard
    private static let prefix = "menubarItem."

    static func isEnabled(_ item: MenuBarItem) -> Bool {
        defaults.bool(forKey: prefix + item.rawValue)
    }

    static func setEnabled(_ item: MenuBarItem, _ enabled: Bool) {
        defaults.set(enabled, forKey: prefix + item.rawValue)
    }

    static func ensureDefaults() {
        for item in MenuBarItem.allCases where defaults.object(forKey: prefix + item.rawValue) == nil {
            let defaultOn: Bool
            switch item {
            case .cpu, .memory: defaultOn = true
            case .pressure: defaultOn = false
            }
            defaults.set(defaultOn, forKey: prefix + item.rawValue)
        }
    }
}
