import AppKit
import FreeShotCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeys: HotkeyManager!
    private var menuBar: MenuBarController!
    private var pendingURLs: [URL] = []
    private var launched = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let registry = ModuleRegistry.shared
        registry.installDefaults()

        hotkeys = HotkeyManager { action in ActionRouter.shared.perform(action) }
        menuBar = MenuBarController(hotkeys: hotkeys)
        registerHotkeys()

        NotificationCenter.default.addObserver(forName: .freeShotHotkeysChanged, object: nil, queue: .main) { [weak self] _ in
            self?.registerHotkeys()
        }

        checkScreenRecordingPermission()

        launched = true
        pendingURLs.forEach { ActionRouter.shared.handle(url: $0) }
        pendingURLs = []
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // A URL can arrive before launch finishes when the app is opened by the URL itself.
        guard launched else { pendingURLs.append(contentsOf: urls); return }
        urls.forEach { ActionRouter.shared.handle(url: $0) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeys?.unregisterAll()
    }

    private func registerHotkeys() {
        hotkeys.register(ModuleRegistry.shared.settings.hotkeys)
        menuBar.rebuild()
    }

    private func checkScreenRecordingPermission() {
        if CGPreflightScreenCaptureAccess() { return }
        CGRequestScreenCaptureAccess()
        let settings = ModuleRegistry.shared.settings
        guard !settings.permissionAlertShown else { return }
        settings.permissionAlertShown = true
        let alert = NSAlert()
        alert.messageText = "FreeShot needs Screen Recording permission"
        alert.informativeText = """
        Open System Settings > Privacy & Security > Screen & System Audio Recording. \
        Turn on FreeShot, then quit and reopen FreeShot.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
