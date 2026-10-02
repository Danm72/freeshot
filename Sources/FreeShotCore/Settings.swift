import CoreGraphics
import Foundation

/// The previous area selection, so "Capture Previous Area" can repeat it.
public struct StoredArea: Codable, Equatable, Sendable {
    public var cocoaRect: CGRect
    public var displayID: UInt32

    public init(cocoaRect: CGRect, displayID: UInt32) {
        self.cocoaRect = cocoaRect
        self.displayID = displayID
    }
}

public enum OverlayCorner: String, Codable, CaseIterable, Sendable {
    case bottomLeft, bottomRight
}

/// FreeShot preferences, stored in a UserDefaults domain (ie.mawla.freeshot for the app).
/// Defaults match Dan's CleanShot setup.
public final class AppSettings: @unchecked Sendable {
    public static let shared = AppSettings(defaults: .standard)

    public let defaults: UserDefaults
    /// Source of first-run hotkeys. Tests inject a fake suite here.
    private let cleanShotDefaults: () -> UserDefaults?

    public init(defaults: UserDefaults,
                cleanShotDefaults: @escaping () -> UserDefaults? = { UserDefaults(suiteName: CleanShotImport.suiteName) }) {
        self.defaults = defaults
        self.cleanShotDefaults = cleanShotDefaults
    }

    enum Key {
        static let saveFolder = "saveFolder"
        static let afterSave = "afterCaptureSave"
        static let afterCopy = "afterCaptureCopy"
        static let afterOverlay = "afterCaptureOverlay"
        static let sounds = "soundsEnabled"
        static let overlaySeconds = "overlayAutoCloseSeconds"
        static let overlayCorner = "overlayCorner"
        static let windowShadow = "windowShadow"
        static let magnifier = "showMagnifier"
        static let crosshair = "showCrosshair"
        static let textSize = "annotateTextSize"
        static let pixelate = "pixelateIntensity"
        static let hotkeys = "hotkeys"
        static let lastArea = "lastArea"
        static let permissionAlertShown = "permissionAlertShown"
        static let recordFPS = "recordFPS"
    }

    public static let defaultSaveFolder = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("screenshots")

    // MARK: Generic helpers

    private func bool(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    private func double(_ key: String, _ fallback: Double) -> Double {
        defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key)
    }

    // MARK: Values

    public var saveFolder: URL {
        get {
            if let p = defaults.string(forKey: Key.saveFolder), !p.isEmpty {
                return URL(fileURLWithPath: (p as NSString).expandingTildeInPath, isDirectory: true)
            }
            return Self.defaultSaveFolder
        }
        set { defaults.set(newValue.path, forKey: Key.saveFolder) }
    }

    public var saveAfterCapture: Bool {
        get { bool(Key.afterSave, true) } set { defaults.set(newValue, forKey: Key.afterSave) }
    }
    public var copyAfterCapture: Bool {
        get { bool(Key.afterCopy, true) } set { defaults.set(newValue, forKey: Key.afterCopy) }
    }
    public var showOverlayAfterCapture: Bool {
        get { bool(Key.afterOverlay, true) } set { defaults.set(newValue, forKey: Key.afterOverlay) }
    }
    public var soundsEnabled: Bool {
        get { bool(Key.sounds, false) } set { defaults.set(newValue, forKey: Key.sounds) }
    }
    public var overlayAutoCloseSeconds: Double {
        get { double(Key.overlaySeconds, 10) } set { defaults.set(newValue, forKey: Key.overlaySeconds) }
    }
    public var overlayCorner: OverlayCorner {
        get { defaults.string(forKey: Key.overlayCorner).flatMap(OverlayCorner.init(rawValue:)) ?? .bottomLeft }
        set { defaults.set(newValue.rawValue, forKey: Key.overlayCorner) }
    }
    public var windowShadow: Bool {
        get { bool(Key.windowShadow, true) } set { defaults.set(newValue, forKey: Key.windowShadow) }
    }
    public var showMagnifier: Bool {
        get { bool(Key.magnifier, true) } set { defaults.set(newValue, forKey: Key.magnifier) }
    }
    public var showCrosshair: Bool {
        get { bool(Key.crosshair, true) } set { defaults.set(newValue, forKey: Key.crosshair) }
    }
    public var annotateTextSize: Double {
        get { double(Key.textSize, 30) } set { defaults.set(newValue, forKey: Key.textSize) }
    }
    public var pixelateIntensity: Double {
        get { double(Key.pixelate, 10) } set { defaults.set(newValue, forKey: Key.pixelate) }
    }
    public var recordFPS: Int {
        get { defaults.object(forKey: Key.recordFPS) == nil ? 60 : defaults.integer(forKey: Key.recordFPS) }
        set { defaults.set(newValue, forKey: Key.recordFPS) }
    }
    public var permissionAlertShown: Bool {
        get { bool(Key.permissionAlertShown, false) } set { defaults.set(newValue, forKey: Key.permissionAlertShown) }
    }

    // MARK: Hotkeys

    /// Hotkeys by action. First read seeds them from CleanShot (or the built-in defaults)
    /// and stores them, so later edits in Settings stick.
    public var hotkeys: [FreeShotAction: HotkeySpec] {
        get {
            if let data = defaults.data(forKey: Key.hotkeys),
               let raw = try? JSONDecoder().decode([String: HotkeySpec].self, from: data) {
                var out: [FreeShotAction: HotkeySpec] = [:]
                for (k, v) in raw { if let a = FreeShotAction(rawValue: k) { out[a] = v } }
                return out
            }
            let seeded = CleanShotImport.hotkeys(from: cleanShotDefaults())
            store(seeded)
            return seeded
        }
        set { store(newValue) }
    }

    public func hotkey(for action: FreeShotAction) -> HotkeySpec? { hotkeys[action] }

    public func setHotkey(_ spec: HotkeySpec?, for action: FreeShotAction) {
        var all = hotkeys
        all[action] = spec
        // One combo drives one action: drop it from any other action.
        if let spec { for (a, s) in all where a != action && s == spec { all[a] = nil } }
        hotkeys = all
    }

    private func store(_ map: [FreeShotAction: HotkeySpec]) {
        let raw = Dictionary(uniqueKeysWithValues: map.map { ($0.key.rawValue, $0.value) })
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        if let data = try? enc.encode(raw) { defaults.set(data, forKey: Key.hotkeys) }
    }

    // MARK: Previous area

    public var lastArea: StoredArea? {
        get { defaults.data(forKey: Key.lastArea).flatMap { try? JSONDecoder().decode(StoredArea.self, from: $0) } }
        set {
            if let newValue, let d = try? JSONEncoder().encode(newValue) { defaults.set(d, forKey: Key.lastArea) }
            else { defaults.removeObject(forKey: Key.lastArea) }
        }
    }
}
