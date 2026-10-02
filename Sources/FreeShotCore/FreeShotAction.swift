import Foundation

/// Every user-facing action FreeShot can run. The raw value is the URL-scheme
/// and CLI name (freeshot://capture/<rawValue>, --capture <rawValue>).
public enum FreeShotAction: String, CaseIterable, Codable, Sendable {
    case fullscreen
    case area
    case window
    case allInOne = "allinone"
    case previousArea = "previous"
    case ocr
    case record

    public var title: String {
        switch self {
        case .fullscreen: return "Capture Fullscreen"
        case .area: return "Capture Area"
        case .window: return "Capture Window"
        case .allInOne: return "All-in-One"
        case .previousArea: return "Capture Previous Area"
        case .ocr: return "Capture Text (OCR)"
        case .record: return "Record Screen"
        }
    }

    /// Parses a URL such as freeshot://capture/area. Returns nil for any other shape.
    public static func from(url: URL) -> FreeShotAction? {
        guard url.scheme?.lowercased() == "freeshot", url.host?.lowercased() == "capture" else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count == 1 else { return nil }
        return FreeShotAction(rawValue: parts[0].lowercased())
    }

    public var url: URL { URL(string: "freeshot://capture/\(rawValue)")! }
}

/// A parsed command line. Only `--capture fullscreen --out <path>` runs headless today.
public struct CLICommand: Equatable, Sendable {
    public var action: FreeShotAction
    public var output: URL?

    public init(action: FreeShotAction, output: URL?) {
        self.action = action
        self.output = output
    }

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case missingValue(String)
        case unknownAction(String)
        case unknownFlag(String)

        public var description: String {
            switch self {
            case .missingValue(let f): return "missing value for \(f)"
            case .unknownAction(let a): return "unknown capture action '\(a)'"
            case .unknownFlag(let f): return "unknown flag '\(f)'"
            }
        }
    }

    /// Returns nil when the arguments do not ask for a CLI run (normal app launch).
    /// Arguments exclude the executable path. macOS adds `-psn_…` and `-NSDocumentRevisionsDebugMode`
    /// style arguments to GUI launches; those are ignored when no --capture flag is present.
    public static func parse(_ args: [String]) throws -> CLICommand? {
        guard args.contains("--capture") else { return nil }
        var action: FreeShotAction?
        var output: URL?
        var i = 0
        while i < args.count {
            let a = args[i]
            switch a {
            case "--capture":
                guard i + 1 < args.count else { throw ParseError.missingValue(a) }
                let v = args[i + 1]
                guard let act = FreeShotAction(rawValue: v.lowercased()) else { throw ParseError.unknownAction(v) }
                action = act
                i += 2
            case "--out":
                guard i + 1 < args.count else { throw ParseError.missingValue(a) }
                let p = (args[i + 1] as NSString).expandingTildeInPath
                output = URL(fileURLWithPath: p)
                i += 2
            default:
                throw ParseError.unknownFlag(a)
            }
        }
        guard let action else { throw ParseError.missingValue("--capture") }
        return CLICommand(action: action, output: output)
    }
}
