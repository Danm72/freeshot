import CoreGraphics
import Foundation

/// One display as the coordinate math needs it.
/// `cocoaFrame` is NSScreen.frame (points, origin bottom-left of the primary display).
public struct DisplayDescriptor: Equatable, Sendable {
    public var id: UInt32
    public var cocoaFrame: CGRect
    public var scale: CGFloat

    public init(id: UInt32, cocoaFrame: CGRect, scale: CGFloat) {
        self.id = id
        self.cocoaFrame = cocoaFrame
        self.scale = scale
    }
}

/// Converts between the 3 spaces FreeShot uses:
/// - Cocoa global points: origin at the bottom-left of the primary display, y up.
/// - CG global points (Quartz, ScreenCaptureKit, CGWindowList): origin top-left of the primary display, y down.
/// - Pixels local to one display: origin top-left of that display, multiplied by its scale.
public struct CoordinateSpace: Sendable {
    public var displays: [DisplayDescriptor]

    /// The primary display is the one whose Cocoa frame has origin (0, 0).
    public var primary: DisplayDescriptor? {
        displays.first { $0.cocoaFrame.origin == .zero } ?? displays.first
    }

    public init(displays: [DisplayDescriptor]) { self.displays = displays }

    private var primaryHeight: CGFloat { primary?.cocoaFrame.height ?? 0 }

    // MARK: Points

    public func cgPoint(fromCocoa p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: primaryHeight - p.y) }
    public func cocoaPoint(fromCG p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: primaryHeight - p.y) }

    // MARK: Rects

    public func cgRect(fromCocoa r: CGRect) -> CGRect {
        let r = r.standardized
        return CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    public func cocoaRect(fromCG r: CGRect) -> CGRect {
        let r = r.standardized
        return CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    /// The display's bounds in CG global points (what CGDisplayBounds returns).
    public func cgBounds(of d: DisplayDescriptor) -> CGRect { cgRect(fromCocoa: d.cocoaFrame) }

    // MARK: Lookup

    public func display(containingCocoa p: CGPoint) -> DisplayDescriptor? {
        // NSRect containment excludes maxX/maxY; a cursor parked on the top or right edge still belongs here.
        displays.first { d in
            let f = d.cocoaFrame
            return p.x >= f.minX && p.x <= f.maxX && p.y >= f.minY && p.y <= f.maxY
        }
    }

    public func display(containingCG p: CGPoint) -> DisplayDescriptor? {
        display(containingCocoa: cocoaPoint(fromCG: p))
    }

    public func display(id: UInt32) -> DisplayDescriptor? { displays.first { $0.id == id } }

    /// The display that holds the largest part of a Cocoa rect.
    public func display(bestFor cocoaRect: CGRect) -> DisplayDescriptor? {
        displays.max { a, b in
            area(a.cocoaFrame.intersection(cocoaRect)) < area(b.cocoaFrame.intersection(cocoaRect))
        }.flatMap { area($0.cocoaFrame.intersection(cocoaRect)) > 0 ? $0 : nil }
    }

    private func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }

    // MARK: Display-local

    /// A Cocoa global rect -> a rect in points local to `d`, origin top-left (the space for
    /// SCStreamConfiguration.sourceRect and for cropping a display snapshot).
    public func localTopLeftPoints(fromCocoa r: CGRect, on d: DisplayDescriptor) -> CGRect {
        let r = r.standardized
        let f = d.cocoaFrame
        return CGRect(x: r.minX - f.minX, y: f.maxY - r.maxY, width: r.width, height: r.height)
    }

    /// A Cocoa global rect -> integral pixels local to `d`, clamped to the display.
    /// Use it to crop a CGImage snapshot of that display.
    public func localPixels(fromCocoa r: CGRect, on d: DisplayDescriptor) -> CGRect {
        let local = localTopLeftPoints(fromCocoa: r, on: d)
        let px = CGRect(x: local.minX * d.scale, y: local.minY * d.scale,
                        width: local.width * d.scale, height: local.height * d.scale).integral
        let bounds = CGRect(x: 0, y: 0, width: d.cocoaFrame.width * d.scale, height: d.cocoaFrame.height * d.scale)
        let clipped = px.intersection(bounds)
        return clipped.isNull ? .zero : clipped
    }

    /// Display-local top-left points -> Cocoa global rect (the inverse of localTopLeftPoints).
    public func cocoaRect(fromLocalTopLeft r: CGRect, on d: DisplayDescriptor) -> CGRect {
        let f = d.cocoaFrame
        return CGRect(x: f.minX + r.minX, y: f.maxY - r.maxY, width: r.width, height: r.height)
    }
}

/// Shift during an area drag. The lock keeps the selection size it had when Shift went down
/// on one axis, and lets the other axis follow the pointer (as macOS ⌘⇧4 does).
public struct AxisLock: Equatable, Sendable {
    public enum Axis: Equatable, Sendable {
        /// x follows the pointer, y stays at the anchor.
        case horizontal
        /// y follows the pointer, x stays at the anchor.
        case vertical
    }

    /// The drag end point when Shift went down.
    public var anchor: CGPoint
    /// The free axis. Nil until the pointer moves `threshold` points from the anchor.
    public private(set) var axis: Axis?
    public var threshold: CGFloat

    public init(anchor: CGPoint, threshold: CGFloat = 2) {
        self.anchor = anchor
        self.threshold = threshold
    }

    /// The locked end point for the pointer at `current`. The first clear move picks the free
    /// axis, and the choice then stays. Before that move, the end stays at the anchor.
    public mutating func end(for current: CGPoint) -> CGPoint {
        let dx = abs(current.x - anchor.x), dy = abs(current.y - anchor.y)
        if axis == nil, max(dx, dy) >= threshold { axis = dx >= dy ? .horizontal : .vertical }
        switch axis {
        case .horizontal: return CGPoint(x: current.x, y: anchor.y)
        case .vertical: return CGPoint(x: anchor.x, y: current.y)
        case nil: return anchor
        }
    }

    /// Moves the anchor with the selection (Space-drag).
    public mutating func shift(by d: CGVector) {
        anchor = CGPoint(x: anchor.x + d.dx, y: anchor.y + d.dy)
    }
}

/// Selection helpers for area selection.
public enum SelectionMath {
    /// The rect between the drag start and the end point. Apply an `AxisLock` to the end first.
    public static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    /// Size label shown while dragging, in pixels: "640 × 480".
    public static func sizeLabel(for pointsRect: CGRect, scale: CGFloat) -> String {
        "\(Int((pointsRect.width * scale).rounded())) × \(Int((pointsRect.height * scale).rounded()))"
    }
}
