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
    private let menuBarIconEnabledKey = "menuBarIconEnabled"
    private let enabledKey = "enabledDisplayItems"
    private let excludedKey = "excludedBundleIDs"

    private init() {
        if defaults.array(forKey: enabledKey) == nil {
            defaults.set([DisplayItem.cpu.rawValue, DisplayItem.memory.rawValue], forKey: enabledKey)
        }
        if defaults.object(forKey: menuBarIconEnabledKey) == nil {
            defaults.set(true, forKey: menuBarIconEnabledKey)
        }
    }

    var isMenuBarIconEnabled: Bool {
        get { defaults.bool(forKey: menuBarIconEnabledKey) }
        set {
            defaults.set(newValue, forKey: menuBarIconEnabledKey)
            if newValue, enabledDisplayItems.isEmpty {
                enabledDisplayItems = [.cpu, .memory]
            } else {
                notifyChange()
            }
        }
    }

    var enabledDisplayItems: Set<DisplayItem> {
        get {
            let raw = defaults.stringArray(forKey: enabledKey) ?? []
            return Set(raw.compactMap { DisplayItem(rawValue: $0) })
        }
        set {
            defaults.set(Array(newValue.map { $0.rawValue }), forKey: enabledKey)
            notifyChange()
        }
    }

    func isEnabled(_ item: DisplayItem) -> Bool {
        isMenuBarIconEnabled && enabledDisplayItems.contains(item)
    }

    func setEnabled(_ item: DisplayItem, _ enabled: Bool) {
        var current = enabledDisplayItems
        if enabled {
            current.insert(item)
        } else {
            current.remove(item)
        }
        enabledDisplayItems = current

        if current.isEmpty {
            isMenuBarIconEnabled = false
        } else if !isMenuBarIconEnabled {
            defaults.set(true, forKey: menuBarIconEnabledKey)
            notifyChange()
        }
    }

    var excludedBundleIDs: Set<String> {
        get {
            Set(defaults.stringArray(forKey: excludedKey) ?? [])
        }
        set {
            defaults.set(Array(newValue), forKey: excludedKey)
            notifyChange()
        }
    }

    func isExcluded(_ bundleID: String) -> Bool {
        excludedBundleIDs.contains(bundleID)
    }

    func setExcluded(_ bundleID: String, _ excluded: Bool) {
        var current = excludedBundleIDs
        if excluded {
            current.insert(bundleID)
        } else {
            current.remove(bundleID)
        }
        excludedBundleIDs = current
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
}
