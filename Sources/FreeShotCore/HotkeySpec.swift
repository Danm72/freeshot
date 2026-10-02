import Foundation

/// Carbon modifier bits (same values as Carbon's cmdKey, shiftKey, optionKey, controlKey).
public enum CarbonModifier {
    public static let command: UInt32 = 1 << 8   // 256
    public static let shift: UInt32 = 1 << 9     // 512
    public static let option: UInt32 = 1 << 11   // 2048
    public static let control: UInt32 = 1 << 12  // 4096
}

/// One global hotkey in Carbon terms, in the same JSON shape CleanShot X stores:
/// {"carbonModifiers":768,"carbonKey":21}
public struct HotkeySpec: Codable, Equatable, Hashable, Sendable {
    public var carbonKey: UInt32
    public var carbonModifiers: UInt32

    public init(carbonKey: UInt32, carbonModifiers: UInt32) {
        self.carbonKey = carbonKey
        self.carbonModifiers = carbonModifiers
    }

    /// Decodes one CleanShot blob. CleanShot stores the JSON as Data; a String is accepted too.
    public static func decodeCleanShot(_ value: Any?) -> HotkeySpec? {
        let data: Data?
        switch value {
        case let d as Data: data = d
        case let s as String: data = s.data(using: .utf8)
        default: data = nil
        }
        guard let data, let spec = try? JSONDecoder().decode(HotkeySpec.self, from: data) else { return nil }
        return spec
    }

    public func encodedJSON() -> Data {
        // Sorted keys keep the output stable for tests and diffs.
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return (try? enc.encode(self)) ?? Data()
    }

    // MARK: Display

    /// "⌘⇧4" style string, in the macOS modifier order ⌃⌥⇧⌘.
    public var displayString: String { modifierSymbols + keyName }

    public var modifierSymbols: String {
        var s = ""
        if carbonModifiers & CarbonModifier.control != 0 { s += "⌃" }
        if carbonModifiers & CarbonModifier.option != 0 { s += "⌥" }
        if carbonModifiers & CarbonModifier.shift != 0 { s += "⇧" }
        if carbonModifiers & CarbonModifier.command != 0 { s += "⌘" }
        return s
    }

    public var keyName: String { KeyCodes.name(for: carbonKey) ?? "Key\(carbonKey)" }

    /// The character an NSMenuItem keyEquivalent needs (lowercase), or "" when there is none.
    public var menuKeyEquivalent: String { KeyCodes.menuEquivalent(for: carbonKey) ?? "" }
}

/// Virtual key codes (kVK_*) to names. Covers letters, digits, F-keys and common keys.
public enum KeyCodes {
    static let table: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N",
        46: "M", 47: ".", 50: "`",
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    public static func name(for keyCode: UInt32) -> String? { table[keyCode] }

    public static func menuEquivalent(for keyCode: UInt32) -> String? {
        guard let n = table[keyCode] else { return nil }
        if n.count == 1, n.unicodeScalars.first!.isASCII { return n.lowercased() }
        if n == "Space" { return " " }
        return nil
    }
}

/// Reads CleanShot X hotkeys and maps them to FreeShot actions.
public enum CleanShotImport {
    public static let suiteName = "pl.maketheweb.cleanshotx"

    /// CleanShot preference keys -> FreeShot action.
    public static let keyMap: [String: FreeShotAction] = [
        "LAVAtakeArea": .area,
        "LAVAtakeFullscreen": .fullscreen,
        "LAVAtakeAllInOne": .allInOne,
    ]

    /// Dan's config: ⌘⇧3 fullscreen, ⌘⇧4 area, ⌘⇧5 All-in-One.
    public static let builtInDefaults: [FreeShotAction: HotkeySpec] = [
        .fullscreen: HotkeySpec(carbonKey: 20, carbonModifiers: CarbonModifier.command | CarbonModifier.shift),
        .area: HotkeySpec(carbonKey: 21, carbonModifiers: CarbonModifier.command | CarbonModifier.shift),
        .allInOne: HotkeySpec(carbonKey: 23, carbonModifiers: CarbonModifier.command | CarbonModifier.shift),
    ]

    /// Maps raw CleanShot preference values to actions. Unknown keys and bad blobs are skipped.
    public static func decode(_ prefs: [String: Any]) -> [FreeShotAction: HotkeySpec] {
        var out: [FreeShotAction: HotkeySpec] = [:]
        for (key, action) in keyMap {
            if let spec = HotkeySpec.decodeCleanShot(prefs[key]) { out[action] = spec }
        }
        return out
    }

    /// Hotkeys from the CleanShot plist when present, else the built-in defaults.
    public static func hotkeys(from defaults: UserDefaults? = UserDefaults(suiteName: suiteName)) -> [FreeShotAction: HotkeySpec] {
        guard let defaults else { return builtInDefaults }
        var prefs: [String: Any] = [:]
        for key in keyMap.keys { if let v = defaults.object(forKey: key) { prefs[key] = v } }
        let decoded = decode(prefs)
        return decoded.isEmpty ? builtInDefaults : decoded
    }
}

/// Builds a Carbon FourCharCode (OSType) from a 4-character ASCII string.
public func fourCC(_ s: String) -> UInt32 {
    precondition(s.utf8.count == 4, "fourCC needs 4 ASCII characters")
    return s.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
}
