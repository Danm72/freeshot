import CoreGraphics
import Foundation

/// Pure geometry for the area overlay, the magnifier and the window picker.
/// Points are Cocoa points unless a name says otherwise.
public enum CaptureGeometry {

    // MARK: Selection

    /// The rect from the drag start to the current point.
    /// - lockAxis (Shift): the selection grows on one axis only.
    /// - fromCenter (Option): the start point is the centre of the rect.
    public static func selection(from start: CGPoint, to current: CGPoint,
                                 lockAxis: Bool = false, fromCenter: Bool = false) -> CGRect {
        guard fromCenter else { return SelectionMath.rect(from: start, to: current, lockAxis: lockAxis) }
        var end = current
        if lockAxis {
            let dx = abs(current.x - start.x), dy = abs(current.y - start.y)
            if dx >= dy { end.y = start.y } else { end.x = start.x }
        }
        let w = abs(end.x - start.x), h = abs(end.y - start.y)
        return CGRect(x: start.x - w, y: start.y - h, width: w * 2, height: h * 2)
    }

    /// Clamps a point into a rect, edges included.
    public static func clamp(_ p: CGPoint, to r: CGRect) -> CGPoint {
        CGPoint(x: min(max(p.x, r.minX), r.maxX), y: min(max(p.y, r.minY), r.maxY))
    }

    /// Rounds a rect to whole pixels at `scale`, so the overlay outline matches the crop.
    public static func pixelAligned(_ r: CGRect, scale: CGFloat) -> CGRect {
        guard scale > 0 else { return r }
        let x0 = (r.minX * scale).rounded() / scale, y0 = (r.minY * scale).rounded() / scale
        let x1 = (r.maxX * scale).rounded() / scale, y1 = (r.maxY * scale).rounded() / scale
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// A drag smaller than this (in points, both axes) counts as a click.
    public static let clickThreshold: CGFloat = 3

    public static func isClick(_ r: CGRect) -> Bool { r.width < clickThreshold && r.height < clickThreshold }

    /// Moves a rect by `delta` but keeps it inside `bounds` (Space-drag moves the whole selection).
    public static func move(_ r: CGRect, by delta: CGVector, within bounds: CGRect) -> CGRect {
        var o = CGRect(x: r.minX + delta.dx, y: r.minY + delta.dy, width: r.width, height: r.height)
        if o.minX < bounds.minX { o.origin.x = bounds.minX }
        if o.maxX > bounds.maxX { o.origin.x = bounds.maxX - o.width }
        if o.minY < bounds.minY { o.origin.y = bounds.minY }
        if o.maxY > bounds.maxY { o.origin.y = bounds.maxY - o.height }
        return o
    }

    // MARK: Arrow nudge

    public enum Arrow: Sendable { case left, right, up, down }

    /// kVK_LeftArrow 123, kVK_RightArrow 124, kVK_DownArrow 125, kVK_UpArrow 126.
    public static func arrow(forKeyCode code: UInt16) -> Arrow? {
        switch code {
        case 123: return .left
        case 124: return .right
        case 125: return .down
        case 126: return .up
        default: return nil
        }
    }

    /// The nudge in Cocoa points (y up): 1 pt, or 10 pt with Shift.
    public static func nudge(_ arrow: Arrow, shift: Bool) -> CGVector {
        let s: CGFloat = shift ? 10 : 1
        switch arrow {
        case .left: return CGVector(dx: -s, dy: 0)
        case .right: return CGVector(dx: s, dy: 0)
        case .up: return CGVector(dx: 0, dy: s)
        case .down: return CGVector(dx: 0, dy: -s)
        }
    }

    // MARK: Magnifier

    /// The square of snapshot pixels the loupe shows, centred on the pixel under the cursor.
    /// `localTopLeft` is the cursor in display-local top-left points. The rect may run past
    /// the image edge; CGImage.cropping clips it and the caller pads.
    public static func magnifierSourcePixels(cursorLocalTopLeft p: CGPoint, scale: CGFloat,
                                             pixelsAcross: Int) -> CGRect {
        let n = max(1, pixelsAcross | 1) // odd, so one pixel sits in the centre
        let cx = Int((p.x * scale).rounded(.down)), cy = Int((p.y * scale).rounded(.down))
        let half = n / 2
        return CGRect(x: cx - half, y: cy - half, width: n, height: n)
    }

    /// Where a box of `size` goes next to the cursor: below-right by `offset`, flipped
    /// to the other side of the cursor on any axis where it would leave `bounds`.
    /// Cocoa coordinates (y up), so "below" means smaller y.
    public static func placeBeside(cursor c: CGPoint, size: CGSize, offset: CGFloat, in bounds: CGRect) -> CGRect {
        var x = c.x + offset
        var y = c.y - offset - size.height
        if x + size.width > bounds.maxX { x = c.x - offset - size.width }
        if y < bounds.minY { y = c.y + offset }
        x = min(max(x, bounds.minX), bounds.maxX - size.width)
        y = min(max(y, bounds.minY), bounds.maxY - size.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    /// Where the W×H label goes: under the selection's bottom-left corner, or inside the
    /// selection's bottom edge when there is no room below.
    public static func sizeLabelFrame(for selection: CGRect, labelSize: CGSize, gap: CGFloat, in bounds: CGRect) -> CGRect {
        var x = selection.minX
        var y = selection.minY - gap - labelSize.height
        if y < bounds.minY { y = selection.minY + gap }
        x = min(max(x, bounds.minX), bounds.maxX - labelSize.width)
        y = min(max(y, bounds.minY), bounds.maxY - labelSize.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: labelSize)
    }

    /// "x, y" for the loupe: display-local top-left points, as macOS shows them.
    public static func coordinateLabel(cursorLocalTopLeft p: CGPoint) -> String {
        "\(Int(p.x.rounded(.down))), \(Int(p.y.rounded(.down)))"
    }
}

// MARK: Window picking

/// One on-screen window in front-to-back order, as CGWindowListCopyWindowInfo lists it.
public struct PickableWindow: Equatable, Sendable {
    public var windowID: UInt32
    /// CG global points (top-left origin).
    public var cgFrame: CGRect
    public var layer: Int
    public var ownerPID: Int32
    public var ownerName: String
    public var title: String

    public init(windowID: UInt32, cgFrame: CGRect, layer: Int, ownerPID: Int32, ownerName: String = "", title: String = "") {
        self.windowID = windowID
        self.cgFrame = cgFrame
        self.layer = layer
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.title = title
    }

    /// Parses one CGWindowList dictionary. Returns nil when a needed key is missing.
    public init?(cgInfo d: [String: Any]) {
        guard let num = (d["kCGWindowNumber"] as? NSNumber)?.uint32Value,
              let bounds = d["kCGWindowBounds"] as? [String: Any],
              let x = (bounds["X"] as? NSNumber)?.doubleValue, let y = (bounds["Y"] as? NSNumber)?.doubleValue,
              let w = (bounds["Width"] as? NSNumber)?.doubleValue, let h = (bounds["Height"] as? NSNumber)?.doubleValue
        else { return nil }
        self.windowID = num
        self.cgFrame = CGRect(x: x, y: y, width: w, height: h)
        self.layer = (d["kCGWindowLayer"] as? NSNumber)?.intValue ?? 0
        self.ownerPID = (d["kCGWindowOwnerPID"] as? NSNumber)?.int32Value ?? 0
        self.ownerName = d["kCGWindowOwnerName"] as? String ?? ""
        self.title = d["kCGWindowName"] as? String ?? ""
    }
}

public enum WindowHitTest {
    /// Keeps normal app windows: layer 0, not ours, big enough to aim at, not fully transparent.
    public static func pickable(_ windows: [PickableWindow], excludingPID own: Int32, minSide: CGFloat = 20) -> [PickableWindow] {
        windows.filter { $0.layer == 0 && $0.ownerPID != own && $0.cgFrame.width >= minSide && $0.cgFrame.height >= minSide }
    }

    /// The front-most window that contains a CG point. `windows` must be front-to-back.
    public static func window(at cgPoint: CGPoint, in windows: [PickableWindow]) -> PickableWindow? {
        windows.first { w in
            let f = w.cgFrame
            return cgPoint.x >= f.minX && cgPoint.x < f.maxX && cgPoint.y >= f.minY && cgPoint.y < f.maxY
        }
    }

    /// True when a window capture's pixel size fits the window: within `tolerance` points of
    /// the frame, with or without a shadow pad of up to `maxShadowPad` points per axis.
    /// A capture that fails this test caught another window (a parent or child), so the
    /// caller falls back to a crop of the frozen snapshot.
    public static func captureSizeFits(pixelSize: CGSize, frame: CGSize, scale: CGFloat,
                                       maxShadowPad: CGFloat = 140, tolerance: CGFloat = 2) -> Bool {
        guard scale > 0 else { return false }
        let w = pixelSize.width / scale, h = pixelSize.height / scale
        let dw = w - frame.width, dh = h - frame.height
        return dw >= -tolerance && dh >= -tolerance && dw <= maxShadowPad + tolerance && dh <= maxShadowPad + tolerance
    }
}

// MARK: All-in-One

/// The HUD buttons, in order. The raw value is the 1-7 shortcut.
public enum AllInOneMode: Int, CaseIterable, Sendable {
    case area = 1, window, fullscreen, previousArea, selfTimer, text, record

    public var title: String {
        switch self {
        case .area: return "Area"
        case .window: return "Window"
        case .fullscreen: return "Fullscreen"
        case .previousArea: return "Previous Area"
        case .selfTimer: return "Self-Timer"
        case .text: return "Capture Text"
        case .record: return "Record Screen"
        }
    }

    /// The letter shortcut shown on the button.
    public var letter: Character {
        switch self {
        case .area: return "A"
        case .window: return "W"
        case .fullscreen: return "F"
        case .previousArea: return "P"
        case .selfTimer: return "T"
        case .text: return "O"
        case .record: return "R"
        }
    }

    public var symbolName: String {
        switch self {
        case .area: return "rectangle.dashed"
        case .window: return "macwindow"
        case .fullscreen: return "display"
        case .previousArea: return "arrow.counterclockwise"
        case .selfTimer: return "timer"
        case .text: return "text.viewfinder"
        case .record: return "record.circle"
        }
    }

    /// Maps a typed character (1-7 or the letter, any case) to a mode.
    public static func from(character: String) -> AllInOneMode? {
        guard let c = character.uppercased().first, character.count == 1 else { return nil }
        if let n = Int(String(c)), let m = AllInOneMode(rawValue: n) { return m }
        return allCases.first { $0.letter == c }
    }
}

// MARK: Self-timer

public enum SelfTimerMath {
    public static let defaultSeconds = 5

    /// The numbers the countdown shows: 5, 4, 3, 2, 1.
    public static func countdown(from seconds: Int) -> [Int] {
        seconds > 0 ? Array((1...seconds).reversed()) : []
    }
}
