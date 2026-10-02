import Foundation

/// Builds CleanShot-style names: "Screenshot 2026-10-02 at 10.21.18@2x.png",
/// "Screen Recording 2026-10-02 at 10.21.18.mp4". A clash gets " (2)", " (3)" and so on.
public struct FilenameGenerator: Sendable {
    public enum Kind: Sendable {
        case screenshot(scale: CGFloat)
        case recording

        var prefix: String {
            switch self {
            case .screenshot: return "Screenshot"
            case .recording: return "Screen Recording"
            }
        }

        var fileExtension: String {
            switch self {
            case .screenshot: return "png"
            case .recording: return "mp4"
            }
        }

        var scaleSuffix: String {
            if case .screenshot(let scale) = self, scale > 1 {
                let s = scale.rounded()
                return "@\(Int(s))x"
            }
            return ""
        }
    }

    public var timeZone: TimeZone

    public init(timeZone: TimeZone = .current) { self.timeZone = timeZone }

    public func timestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f.string(from: date)
    }

    /// The base file name with no collision suffix.
    public func baseName(kind: Kind, date: Date) -> String {
        "\(kind.prefix) \(timestamp(date))\(kind.scaleSuffix).\(kind.fileExtension)"
    }

    /// A URL in `folder` that does not exist yet. The suffix goes after "@2x":
    /// "Screenshot … at 10.21.18@2x (2).png".
    public func uniqueURL(in folder: URL, kind: Kind, date: Date,
                          exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let stem = "\(kind.prefix) \(timestamp(date))\(kind.scaleSuffix)"
        let ext = kind.fileExtension
        var url = folder.appendingPathComponent("\(stem).\(ext)")
        var n = 2
        while exists(url) {
            url = folder.appendingPathComponent("\(stem) (\(n)).\(ext)")
            n += 1
        }
        return url
    }
}
