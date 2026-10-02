import CoreGraphics
import Foundation

/// One recognised line of text from Vision.
/// `box` is normalised (0...1) with the origin at the bottom-left, as Vision returns it.
public struct OCRLine: Equatable, Sendable {
    public var text: String
    public var box: CGRect

    public init(text: String, box: CGRect) {
        self.text = text
        self.box = box
    }
}

/// Turns Vision observations into the clipboard text: top to bottom, left to right,
/// one output line for each visual row, so the line breaks stay.
public enum OCRTextAssembler {
    public static func assemble(_ lines: [OCRLine]) -> String {
        let items = lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !items.isEmpty else { return "" }
        // Highest first (Vision y goes up).
        let sorted = items.sorted { $0.box.midY > $1.box.midY }
        var rows: [[OCRLine]] = []
        for item in sorted {
            if let last = rows.last, let ref = last.first, sameRow(ref, item) {
                rows[rows.count - 1].append(item)
            } else {
                rows.append([item])
            }
        }
        return rows.map { row in
            row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ")
        }.joined(separator: "\n")
    }

    /// Two boxes are on the same row when their vertical centres are closer than
    /// half the smaller box height.
    static func sameRow(_ a: OCRLine, _ b: OCRLine) -> Bool {
        let tolerance = min(a.box.height, b.box.height) / 2
        return abs(a.box.midY - b.box.midY) < tolerance
    }

    /// The URLs and e-mail links in the text.
    public static func links(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, options: [], range: range).compactMap(\.url)
    }

    /// Toast text, e.g. "Copied 3 lines · 1 link".
    public static func toastMessage(for text: String) -> String {
        if text.isEmpty { return "No text found" }
        let lineCount = text.split(separator: "\n", omittingEmptySubsequences: true).count
        var s = "Copied \(lineCount) line\(lineCount == 1 ? "" : "s")"
        let linkCount = links(in: text).count
        if linkCount > 0 { s += " · \(linkCount) link\(linkCount == 1 ? "" : "s")" }
        return s
    }
}
