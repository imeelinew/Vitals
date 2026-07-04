import AppKit

@main
enum VitalsApp {
    static func main() {
        guard PlatformRequirements.enforceMinimumOSVersion() else {
            exit(1)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
