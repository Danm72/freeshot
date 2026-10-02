import AppKit
import FreeShotCore

/// The status-bar icon and its menu. A red icon means a recording runs; a click stops it.
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let hotkeys: HotkeyManager

    /// Actions shown in the menu, in CleanShot's order.
    private let menuActions: [FreeShotAction] = [.allInOne, .area, .previousArea, .fullscreen, .window, .ocr, .record]

    init(hotkeys: HotkeyManager) {
        self.hotkeys = hotkeys
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusButtonClicked)
        }
        updateIcon()
        NotificationCenter.default.addObserver(forName: .freeShotRecordingStateChanged, object: nil, queue: .main) { [weak self] _ in
            self?.updateIcon()
        }
        NotificationCenter.default.addObserver(forName: .freeShotHistoryChanged, object: nil, queue: .main) { [weak self] _ in
            self?.rebuild()
        }
    }

    private var isRecording: Bool { ModuleRegistry.shared.recorder.isRecording }

    func updateIcon() {
        guard let button = statusItem.button else { return }
        if isRecording {
            let img = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Stop recording")
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            button.image = img?.withSymbolConfiguration(config)
            button.image?.isTemplate = false
            button.toolTip = "FreeShot: click to stop recording"
            // No menu while recording, so a click goes to statusButtonClicked.
            statusItem.menu = nil
        } else {
            let img = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "FreeShot")
            img?.isTemplate = true
            button.image = img
            button.toolTip = "FreeShot"
            statusItem.menu = menu
        }
    }

    @objc private func statusButtonClicked() {
        if isRecording { ActionRouter.shared.stopRecording() }
    }

    func menuNeedsUpdate(_ menu: NSMenu) { rebuild() }

    func rebuild() {
        menu.removeAllItems()
        let registry = ModuleRegistry.shared
        let keys = registry.settings.hotkeys

        for action in menuActions {
            let item = NSMenuItem(title: action.title, action: #selector(runAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action.rawValue
            if let spec = keys[action], !spec.menuKeyEquivalent.isEmpty {
                // Shown for reference only; the Carbon hotkey does the work.
                item.keyEquivalent = spec.menuKeyEquivalent
                item.keyEquivalentModifierMask = Self.modifierMask(spec.carbonModifiers)
            }
            menu.addItem(item)
        }

        if !ScreenRecordingPermission.isGranted {
            menu.addItem(.separator())
            let item = NSMenuItem(title: "⚠︎ Screen Recording not granted", action: #selector(openPermissionPane),
                                  keyEquivalent: "")
            item.target = self
            item.toolTip = "Click to open System Settings. Turn on FreeShot, then reopen FreeShot."
            menu.addItem(item)
        }

        if !hotkeys.failures.isEmpty {
            menu.addItem(.separator())
            for f in hotkeys.failures {
                let item = NSMenuItem(title: "⚠︎ \(f.message)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                item.toolTip = "\(f.action.title) has no hotkey. Quit the other app (CleanShot?) and reopen FreeShot."
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let recentItem = NSMenuItem(title: "Recent Captures", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu()
        let recent = registry.history.recent(10)
        if recent.isEmpty {
            let none = NSMenuItem(title: "None yet", action: nil, keyEquivalent: "")
            none.isEnabled = false
            recentMenu.addItem(none)
        } else {
            for entry in recent {
                let item = NSMenuItem(title: entry.url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = entry.path
                item.toolTip = "Click to open. ⌥-click to show in Finder."
                recentMenu.addItem(item)
            }
        }
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)

        let folder = NSMenuItem(title: "Open Screenshots Folder", action: #selector(openFolder), keyEquivalent: "")
        folder.target = self
        menu.addItem(folder)

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: "Quit FreeShot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    static func modifierMask(_ carbon: UInt32) -> NSEvent.ModifierFlags {
        var m: NSEvent.ModifierFlags = []
        if carbon & CarbonModifier.command != 0 { m.insert(.command) }
        if carbon & CarbonModifier.shift != 0 { m.insert(.shift) }
        if carbon & CarbonModifier.option != 0 { m.insert(.option) }
        if carbon & CarbonModifier.control != 0 { m.insert(.control) }
        return m
    }

    @objc private func runAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = FreeShotAction(rawValue: raw) else { return }
        // Let the menu close first, so it is not in the capture.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { ActionRouter.shared.perform(action) }
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        let url = URL(fileURLWithPath: path)
        if NSEvent.modifierFlags.contains(.option) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openPermissionPane() { ScreenRecordingPermission.openSettings() }

    @objc private func openFolder() {
        let folder = ModuleRegistry.shared.settings.saveFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    @objc private func openSettings() {
        NSApp.activate()
        ActionRouter.shared.showSettings()
    }
}
