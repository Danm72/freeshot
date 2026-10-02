import AppKit
import FreeShotCore
import ServiceManagement
import SwiftUI

/// The Settings window: SwiftUI content in a plain NSWindow, one instance reused.
final class SettingsWindowController: SettingsUI {
    private var window: NSWindow?
    private let model = SettingsModel()

    func show() {
        dispatchPrecondition(condition: .onQueue(.main))
        model.reload()
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(model: model))
            let w = NSWindow(contentViewController: host)
            w.title = "FreeShot Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Bridges AppSettings to SwiftUI. Each change writes straight to UserDefaults.
final class SettingsModel: ObservableObject {
    private let settings = ModuleRegistry.shared.settings

    @Published var saveFolder: String = ""
    @Published var saveAfterCapture = true { didSet { settings.saveAfterCapture = saveAfterCapture } }
    @Published var copyAfterCapture = true { didSet { settings.copyAfterCapture = copyAfterCapture } }
    @Published var showOverlay = true { didSet { settings.showOverlayAfterCapture = showOverlay } }
    @Published var sounds = false { didSet { settings.soundsEnabled = sounds } }
    @Published var overlaySeconds: Double = 10 { didSet { settings.overlayAutoCloseSeconds = overlaySeconds } }
    @Published var hotkeys: [FreeShotAction: HotkeySpec] = [:]
    @Published var launchAtLogin = false
    @Published var loginError: String?
    @Published var recordingAction: FreeShotAction?
    @Published var recorderHint: String?

    private var monitor: Any?
    private var loading = false

    func reload() {
        saveFolder = settings.saveFolder.path
        saveAfterCapture = settings.saveAfterCapture
        copyAfterCapture = settings.copyAfterCapture
        showOverlay = settings.showOverlayAfterCapture
        sounds = settings.soundsEnabled
        overlaySeconds = settings.overlayAutoCloseSeconds
        hotkeys = settings.hotkeys
        launchAtLogin = SMAppService.mainApp.status == .enabled
        loginError = nil
    }

    // MARK: Save folder

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.saveFolder
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveFolder = url
            saveFolder = url.path
        }
    }

    // MARK: Launch at login

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Cannot change: \(error.localizedDescription). Run FreeShot from /Applications."
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Hotkey recorder

    func startRecording(_ action: FreeShotAction) {
        stopRecording()
        recordingAction = action
        recorderHint = "Press the new shortcut. Esc cancels, Delete clears."
        NotificationCenter.default.post(name: .freeShotHotkeysSuspend, object: nil, userInfo: ["suspended": true])
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let action = self.recordingAction else { return event }
            let raw = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
            switch HotkeyRecorderRules.evaluate(keyCode: UInt32(event.keyCode), cocoaModifiers: raw) {
            case .cancel:
                self.stopRecording()
            case .clear:
                self.apply(nil, for: action)
                self.stopRecording()
            case .accept(let spec):
                self.apply(spec, for: action)
                self.stopRecording()
            case .reject(let why):
                self.recorderHint = why
            }
            return nil
        }
    }

    func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        let wasRecording = monitor != nil
        monitor = nil
        recordingAction = nil
        recorderHint = nil
        if wasRecording {
            NotificationCenter.default.post(name: .freeShotHotkeysSuspend, object: nil, userInfo: ["suspended": false])
        }
    }

    func clear(_ action: FreeShotAction) { apply(nil, for: action) }

    func restoreDefaults() {
        settings.hotkeys = CleanShotImport.hotkeys()
        hotkeys = settings.hotkeys
        NotificationCenter.default.post(name: .freeShotHotkeysChanged, object: nil)
    }

    private func apply(_ spec: HotkeySpec?, for action: FreeShotAction) {
        settings.setHotkey(spec, for: action)
        hotkeys = settings.hotkeys
        // AppDelegate re-registers every hotkey from settings on this notification.
        NotificationCenter.default.post(name: .freeShotHotkeysChanged, object: nil)
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Save") {
                HStack {
                    Text(model.saveFolder).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose…") { model.chooseFolder() }
                }
            }
            Section("After capture") {
                Toggle("Save to the folder", isOn: $model.saveAfterCapture)
                Toggle("Copy to the clipboard", isOn: $model.copyAfterCapture)
                Toggle("Show the Quick Access Overlay", isOn: $model.showOverlay)
                Stepper(value: $model.overlaySeconds, in: 0...60, step: 1) {
                    Text(model.overlaySeconds == 0 ? "Overlay stays open"
                         : "Overlay closes after \(Int(model.overlaySeconds)) s")
                }
                Toggle("Play sounds", isOn: $model.sounds)
            }
            Section("Shortcuts") {
                ForEach(FreeShotAction.allCases, id: \.self) { action in
                    HotkeyRow(model: model, action: action)
                }
                if let hint = model.recorderHint {
                    Text(hint).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("Restore CleanShot shortcuts") { model.restoreDefaults() }
                }
            }
            Section("General") {
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin },
                                                        set: { model.setLaunchAtLogin($0) }))
                if let err = model.loginError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onDisappear { model.stopRecording() }
    }
}

struct HotkeyRow: View {
    @ObservedObject var model: SettingsModel
    let action: FreeShotAction

    var body: some View {
        let recording = model.recordingAction == action
        HStack {
            Text(action.title)
            Spacer()
            Button {
                recording ? model.stopRecording() : model.startRecording(action)
            } label: {
                Text(recording ? "Type shortcut…" : (model.hotkeys[action]?.displayString ?? "Record Shortcut"))
                    .frame(minWidth: 110)
                    .foregroundStyle(recording ? Color.accentColor : (model.hotkeys[action] == nil ? .secondary : .primary))
            }
            if model.hotkeys[action] != nil && !recording {
                Button {
                    model.clear(action)
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove this shortcut")
            }
        }
    }
}
