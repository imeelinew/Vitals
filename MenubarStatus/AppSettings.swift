import Foundation

enum DisplayItem: String, CaseIterable {
    case cpu
    case memory
    case pressure

    var label: String {
        switch self {
        case .cpu: return "CPU 占用率"
        case .memory: return "内存占用率"
        case .pressure: return "内存压力"
        }
    }
}

final class AppSettings {
    static let shared = AppSettings()
    static let didChangeNotification = Notification.Name("AppSettings.didChange")

    private let defaults = UserDefaults.standard
    private let enabledKey = "enabledDisplayItems"

    private init() {
        if defaults.array(forKey: enabledKey) == nil {
            defaults.set([DisplayItem.cpu.rawValue, DisplayItem.memory.rawValue], forKey: enabledKey)
        }
    }

    var enabledDisplayItems: Set<DisplayItem> {
        get {
            let raw = defaults.stringArray(forKey: enabledKey) ?? []
            let items = Set(raw.compactMap { DisplayItem(rawValue: $0) })
            return items.isEmpty ? [.cpu, .memory] : items
        }
        set {
            defaults.set(Array(newValue.map { $0.rawValue }), forKey: enabledKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    func isEnabled(_ item: DisplayItem) -> Bool {
        enabledDisplayItems.contains(item)
    }

    func setEnabled(_ item: DisplayItem, _ enabled: Bool) {
        var current = enabledDisplayItems
        if enabled {
            current.insert(item)
        } else if current.count > 1 {
            current.remove(item)
        } else {
            return
        }
        enabledDisplayItems = current
    }
}
