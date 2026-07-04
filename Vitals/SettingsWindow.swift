import AppKit
import SwiftUI

@available(macOS 26.0, *)
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        NSApp.setActivationPolicy(.regular)

        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        NSApp.setActivationPolicy(.regular)

        let hosting = NSHostingController(rootView: SettingsView())
        let win = NSWindow(contentViewController: hosting)
        win.title = SettingsView.SettingsPage.menubar.title
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        win.collectionBehavior = [.fullScreenNone, .fullScreenDisallowsTiling]
        win.isReleasedWhenClosed = false
        let defaultWindowFrameSize = NSSize(width: 950, height: 830)
        let minimumContentSize = NSSize(width: 950, height: 830)
        win.minSize = win.frameRect(forContentRect: NSRect(origin: .zero, size: minimumContentSize)).size
        win.setFrame(NSRect(origin: win.frame.origin, size: defaultWindowFrameSize), display: false)
        win.center()
        win.delegate = self
        window = win

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }

    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        window.screen?.visibleFrame ?? newFrame
    }

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        true
    }
}
