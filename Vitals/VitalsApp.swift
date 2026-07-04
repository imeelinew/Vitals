import AppKit
import SwiftUI

@main
struct VitalsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        if !PlatformRequirements.enforceMinimumOSVersion() {
            exit(1)
        }
    }

    var body: some Scene {
        Window("设置", id: "settings") {
            SettingsWindowRoot()
        }
        .defaultSize(width: 700, height: 610)
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

@available(macOS 26.0, *)
private struct SettingsWindowRoot: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        SettingsView()
            .frame(minWidth: 700, minHeight: 610)
            .onAppear {
                SettingsWindowOpener.register {
                    openWindow(id: "settings")
                }
            }
    }
}

@MainActor
enum SettingsWindowOpener {
    private static var openHandler: (() -> Void)?

    static func register(_ handler: @escaping () -> Void) {
        openHandler = handler
    }

    static func show() {
        NSApp.setActivationPolicy(.regular)
        if let openHandler {
            openHandler()
        } else {
            DispatchQueue.main.async {
                openHandler?()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
