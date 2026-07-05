import Foundation

enum LaunchAtLogin {
    private static let agentPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/com.eli.Vitals.plist")

    private static func plistData() throws -> Data {
        let exePath = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/Vitals").path
        let dict: [String: Any] = [
            "Label": "com.eli.Vitals",
            "ProgramArguments": [exePath],
            "RunAtLoad": true,
            "KeepAlive": false
        ]
        return try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: agentPath.path)
    }

    static func enable() throws {
        let dir = agentPath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try plistData().write(to: agentPath)
    }

    static func disable() throws {
        try? FileManager.default.removeItem(at: agentPath)
    }
}
