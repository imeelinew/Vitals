import AppKit

enum PlatformRequirements {
    static let minimumMajorVersion = 26

    @discardableResult
    static func enforceMinimumOSVersion() -> Bool {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        guard version.majorVersion >= minimumMajorVersion else {
            let alert = NSAlert()
            alert.messageText = "Vitals 无法运行"
            alert.informativeText = "Vitals 需要 macOS \(minimumMajorVersion) 或更高版本。当前系统版本过低，无法使用此应用。"
            alert.alertStyle = .critical
            alert.runModal()
            return false
        }
        return true
    }
}
