import CoreGraphics
import Foundation

/// Stream geometry for a screen recording on one display.
public struct RecordingGeometry: Equatable, Sendable {
    /// The area to record, in points local to the display, origin top-left
    /// (the space for SCStreamConfiguration.sourceRect).
    public var sourceRect: CGRect
    /// Output size in pixels. Both values are even, because H.264 needs even sizes.
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// The recorded area in Cocoa global points, after the clip to the display.
    public var cocoaRect: CGRect

    public init(sourceRect: CGRect, pixelWidth: Int, pixelHeight: Int, cocoaRect: CGRect) {
        self.sourceRect = sourceRect
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.cocoaRect = cocoaRect
    }

    /// Rounds down to an even number, with a minimum of 2.
    public static func even(_ v: CGFloat) -> Int {
        let n = Int(v.rounded(.down))
        return max(2, n - n % 2)
    }

    /// Builds the geometry. `rect` is in Cocoa global points; nil records the whole display.
    /// Returns nil when the rect does not touch the display or is smaller than 1 point.
    public static func make(rect: CGRect?, on display: DisplayDescriptor, space: CoordinateSpace) -> RecordingGeometry? {
        let full = display.cocoaFrame
        let wanted = (rect ?? full).standardized.integral
        let clipped = wanted.intersection(full)
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { return nil }
        // Make the point size match the even pixel size, so the video is not stretched.
        let w = even(clipped.width * display.scale)
        let h = even(clipped.height * display.scale)
        let pointRect = CGRect(x: clipped.minX, y: clipped.maxY - CGFloat(h) / display.scale,
                               width: CGFloat(w) / display.scale, height: CGFloat(h) / display.scale)
        let source = space.localTopLeftPoints(fromCocoa: pointRect, on: display)
        return RecordingGeometry(sourceRect: source, pixelWidth: w, pixelHeight: h, cocoaRect: pointRect)
    }
}
