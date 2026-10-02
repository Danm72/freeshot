import Foundation

/// Pure rules for the Settings hotkey recorder.
public enum HotkeyRecorderRules {
    // NSEvent.ModifierFlags raw values (AppKit is not needed in Core for these).
    public static let cocoaShift: UInt = 1 << 17
    public static let cocoaControl: UInt = 1 << 18
    public static let cocoaOption: UInt = 1 << 19
    public static let cocoaCommand: UInt = 1 << 20

    /// NSEvent.ModifierFlags.rawValue -> Carbon modifier bits.
    public static func carbonModifiers(fromCocoa raw: UInt) -> UInt32 {
        var m: UInt32 = 0
        if raw & cocoaCommand != 0 { m |= CarbonModifier.command }
        if raw & cocoaShift != 0 { m |= CarbonModifier.shift }
        if raw & cocoaOption != 0 { m |= CarbonModifier.option }
        if raw & cocoaControl != 0 { m |= CarbonModifier.control }
        return m
    }

    static let functionKeys: Set<UInt32> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
    static let modifierOnlyKeys: Set<UInt32> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    public enum Verdict: Equatable, Sendable {
        case accept(HotkeySpec)
        case cancel
        case clear
        case reject(String)
    }

    /// What a key press means while the recorder is armed.
    /// Esc with no modifiers cancels; Delete or Backspace with no modifiers clears.
    /// A combo needs ⌘, ⌃ or ⌥, except for the F-keys.
    public static func evaluate(keyCode: UInt32, cocoaModifiers raw: UInt) -> Verdict {
        let mods = carbonModifiers(fromCocoa: raw)
        if modifierOnlyKeys.contains(keyCode) { return .reject("Press a key with the modifiers") }
        if mods == 0 && keyCode == 53 { return .cancel }
        if mods == 0 && (keyCode == 51 || keyCode == 117) { return .clear }
        let strong = CarbonModifier.command | CarbonModifier.option | CarbonModifier.control
        if mods & strong == 0 && !functionKeys.contains(keyCode) {
            return .reject("Use ⌘, ⌃ or ⌥ in the shortcut")
        }
        return .accept(HotkeySpec(carbonKey: keyCode, carbonModifiers: mods))
    }
}
