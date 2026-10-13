import ApplicationServices

/// Owns the event-driven window tools in the existing Vitals process.
final class WindowManagementService {
    private var windows: WindowController?
    private var hotKeys: HotKeyManager?
    private var workspace: WorkspaceMonitor?

    func start() {
        guard windows == nil else { return }
        if !AXIsProcessTrusted() {
            AXIsProcessTrustedWithOptions([
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary)
        }
        let windows = WindowController()
        self.windows = windows
        hotKeys = HotKeyManager(windows: windows)
        workspace = WorkspaceMonitor(windows: windows)
    }

    func stop() {
        hotKeys = nil
        workspace = nil
        windows = nil
    }
}
