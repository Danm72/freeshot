import CoreGraphics
import Foundation

/// The tools in the Annotate toolbar, in toolbar order.
public enum AnnotationTool: String, Codable, CaseIterable, Sendable {
    case select, arrow, line, rectangle, filledRectangle, ellipse, text, highlighter, pen, pixelate, blur, counter, crop

    public var title: String {
        switch self {
        case .select: return "Select"
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .rectangle: return "Rectangle"
        case .filledRectangle: return "Filled Rectangle"
        case .ellipse: return "Ellipse"
        case .text: return "Text"
        case .highlighter: return "Highlighter"
        case .pen: return "Pen"
        case .pixelate: return "Pixelate"
        case .blur: return "Blur"
        case .counter: return "Counter"
        case .crop: return "Crop"
        }
    }

    /// SF Symbol for the toolbar button.
    public var symbolName: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .filledRectangle: return "rectangle.fill"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .highlighter: return "highlighter"
        case .pen: return "pencil.tip"
        case .pixelate: return "squareshape.split.3x3"
        case .blur: return "drop"
        case .counter: return "1.circle"
        case .crop: return "crop"
        }
    }

    /// Single-key shortcut in the editor (no modifiers).
    public var shortcut: Character {
        switch self {
        case .select: return "v"
        case .arrow: return "a"
        case .line: return "l"
        case .rectangle: return "r"
        case .filledRectangle: return "f"
        case .ellipse: return "o"
        case .text: return "t"
        case .highlighter: return "h"
        case .pen: return "p"
        case .pixelate: return "x"
        case .blur: return "b"
        case .counter: return "n"
        case .crop: return "c"
        }
    }

    public static func forShortcut(_ c: Character) -> AnnotationTool? {
        let lower = Character(c.lowercased())
        return allCases.first { $0.shortcut == lower }
    }

    /// The annotation kind this tool makes, or nil for select and crop.
    public var kind: AnnotationKind? { AnnotationKind(rawValue: rawValue) }
}

/// What an annotation draws. Raw values match AnnotationTool.
public enum AnnotationKind: String, Codable, CaseIterable, Sendable {
    case arrow, line, rectangle, filledRectangle, ellipse, text, highlighter, pen, pixelate, blur, counter

    /// Kinds defined by two corner points.
    public var isBoxed: Bool {
        switch self {
        case .rectangle, .filledRectangle, .ellipse, .pixelate, .blur: return true
        default: return false
        }
    }

    public var isFreehand: Bool { self == .pen || self == .highlighter }
    public var isSegment: Bool { self == .arrow || self == .line }
}

/// An sRGB colour with components 0...1.
public struct RGBAColor: Codable, Equatable, Hashable, Sendable {
    public var r: Double, g: Double, b: Double, a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    /// Parses "#RRGGBB" or "#RRGGBBAA" (the # is optional).
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        if s.count == 6 {
            self.init(r: Double((v >> 16) & 0xFF) / 255, g: Double((v >> 8) & 0xFF) / 255, b: Double(v & 0xFF) / 255)
        } else {
            self.init(r: Double((v >> 24) & 0xFF) / 255, g: Double((v >> 16) & 0xFF) / 255,
                      b: Double((v >> 8) & 0xFF) / 255, a: Double(v & 0xFF) / 255)
        }
    }

    public var hex: String {
        func c(_ x: Double) -> String { String(format: "%02X", Int((min(max(x, 0), 1) * 255).rounded())) }
        return "#" + c(r) + c(g) + c(b) + (a < 1 ? c(a) : "")
    }

    public var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

    public func withAlpha(_ alpha: Double) -> RGBAColor { RGBAColor(r: r, g: g, b: b, a: alpha) }

    /// Relative luminance (Rec. 709 weights on the sRGB values).
    public var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    /// Text colour that reads on top of this colour.
    public var contrastingText: RGBAColor { luminance > 0.6 ? .black : .white }

    public static let red = RGBAColor(hex: "#FF3B30")!
    public static let orange = RGBAColor(hex: "#FF9500")!
    public static let yellow = RGBAColor(hex: "#FFCC00")!
    public static let green = RGBAColor(hex: "#34C759")!
    public static let blue = RGBAColor(hex: "#007AFF")!
    public static let purple = RGBAColor(hex: "#AF52DE")!
    public static let black = RGBAColor(r: 0, g: 0, b: 0)
    public static let white = RGBAColor(r: 1, g: 1, b: 1)

    public static let palette: [RGBAColor] = [.red, .orange, .yellow, .green, .blue, .purple, .black, .white]
}

/// One annotation. All geometry and sizes are in image pixels, origin top-left, y down.
public struct Annotation: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: AnnotationKind
    /// Segment and boxed kinds: [start, end]. Freehand: the stroke. Text: [top-left]. Counter: [centre].
    public var points: [CGPoint]
    public var color: RGBAColor
    public var lineWidth: CGFloat
    public var text: String
    public var fontSize: CGFloat
    /// Counter number.
    public var number: Int
    /// Pixelate block size or blur radius, in pixels.
    public var intensity: CGFloat

    public init(id: UUID = UUID(), kind: AnnotationKind, points: [CGPoint], color: RGBAColor = .red,
                lineWidth: CGFloat = 8, text: String = "", fontSize: CGFloat = 60, number: Int = 0,
                intensity: CGFloat = 20) {
        self.id = id
        self.kind = kind
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
        self.text = text
        self.fontSize = fontSize
        self.number = number
        self.intensity = intensity
    }

    public var start: CGPoint { points.first ?? .zero }
    public var end: CGPoint { points.last ?? .zero }

    /// The box between the first and last point (boxed and segment kinds).
    public var rect: CGRect { AnnotateGeometry.rect(from: start, to: end) }

    public mutating func translate(dx: CGFloat, dy: CGFloat) {
        points = points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
    }

    /// True when the annotation is too small to keep (a click with a drag tool).
    public var isDegenerate: Bool {
        switch kind {
        case .text: return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .counter: return false
        case .pen, .highlighter:
            return points.count < 2 && AnnotateGeometry.distance(start, end) < 1
        case .arrow, .line: return AnnotateGeometry.distance(start, end) < 3
        default: return rect.width < 3 || rect.height < 3
        }
    }
}

/// Everything undo restores.
public struct AnnotationState: Equatable, Sendable {
    public var annotations: [Annotation] = []
    /// Applied crop in image pixels, or nil for the whole image.
    public var crop: CGRect?

    public init(annotations: [Annotation] = [], crop: CGRect? = nil) {
        self.annotations = annotations
        self.crop = crop
    }
}

/// The editable annotation list with snapshot undo/redo.
public final class AnnotationDocument {
    public let imageSize: CGSize
    public private(set) var state = AnnotationState()
    private var undoStack: [AnnotationState] = []
    private var redoStack: [AnnotationState] = []
    private var changeCount = 0
    private var savedChangeCount = 0
    public let undoLimit: Int

    public init(imageSize: CGSize, undoLimit: Int = 200) {
        self.imageSize = imageSize
        self.undoLimit = undoLimit
    }

    public var annotations: [Annotation] { state.annotations }
    public var crop: CGRect? { state.crop }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var isDirty: Bool { changeCount != savedChangeCount }
    public var isEmpty: Bool { state.annotations.isEmpty && state.crop == nil }

    public func annotation(id: UUID) -> Annotation? { state.annotations.first { $0.id == id } }

    /// Records the current state as one undo step. Call once before a run of
    /// `update(..., registerUndo: false)` calls, such as a drag-move.
    public func beginChange() {
        undoStack.append(state)
        if undoStack.count > undoLimit { undoStack.removeFirst(undoStack.count - undoLimit) }
        redoStack.removeAll()
        changeCount += 1
    }

    public func add(_ a: Annotation) {
        beginChange()
        state.annotations.append(a)
    }

    public func remove(id: UUID) {
        guard state.annotations.contains(where: { $0.id == id }) else { return }
        beginChange()
        state.annotations.removeAll { $0.id == id }
    }

    public func update(id: UUID, registerUndo: Bool = true, _ body: (inout Annotation) -> Void) {
        guard let i = state.annotations.firstIndex(where: { $0.id == id }) else { return }
        var copy = state.annotations[i]
        body(&copy)
        guard copy != state.annotations[i] else { return }
        if registerUndo { beginChange() }
        state.annotations[i] = copy
    }

    /// Sets the crop after clamping it to the image. A crop that clamps to nothing clears it.
    public func setCrop(_ r: CGRect?) {
        let clamped = r.flatMap { AnnotateGeometry.clampCrop($0, to: imageSize) }
        guard clamped != state.crop else { return }
        beginChange()
        state.crop = clamped
    }

    public func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(state)
        state = prev
        changeCount -= 1
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(state)
        state = next
        changeCount += 1
    }

    public func markSaved() { savedChangeCount = changeCount }

    /// The number the next counter gets: one more than the highest counter on the canvas.
    public func nextCounterNumber() -> Int {
        (state.annotations.filter { $0.kind == .counter }.map(\.number).max() ?? 0) + 1
    }

    /// The topmost annotation under `p`, within `tolerance` pixels.
    public func hitTest(_ p: CGPoint, tolerance: CGFloat) -> UUID? {
        state.annotations.last { AnnotationHitTest.hits($0, point: p, tolerance: tolerance) }?.id
    }
}
