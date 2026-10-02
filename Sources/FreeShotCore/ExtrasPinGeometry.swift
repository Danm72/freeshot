import CoreGraphics
import Foundation

/// Size math for a pinned image window.
public enum PinGeometry {
    public static let minSide: CGFloat = 40
    public static let opacitySteps: [CGFloat] = [1.0, 0.75, 0.5, 0.25]

    /// The first frame for a pin: the image at its point size, shrunk to fit 80 % of the
    /// visible screen, centred on `center` and kept inside `visible`.
    public static func initialFrame(imagePointSize: CGSize, center: CGPoint, visible: CGRect) -> CGRect {
        let maxW = visible.width * 0.8, maxH = visible.height * 0.8
        let fit = min(1, maxW / max(imagePointSize.width, 1), maxH / max(imagePointSize.height, 1))
        let size = CGSize(width: max(minSide, (imagePointSize.width * fit).rounded()),
                          height: max(minSide, (imagePointSize.height * fit).rounded()))
        var origin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        return CGRect(origin: origin, size: size)
    }

    /// Scales `frame` by `factor` around `anchor` (a point in the same space), keeps the
    /// aspect ratio, and clamps so the short side is at least `minSide` and the long side
    /// at most `maxLongSide`.
    public static func scaled(_ frame: CGRect, by factor: CGFloat, around anchor: CGPoint,
                              maxLongSide: CGFloat = 8000) -> CGRect {
        guard frame.width > 0, frame.height > 0, factor > 0 else { return frame }
        let shortSide = min(frame.width, frame.height)
        let longSide = max(frame.width, frame.height)
        let lo = minSide / shortSide
        let hi = maxLongSide / longSide
        let f = min(max(factor, lo), max(hi, lo))
        let w = frame.width * f, h = frame.height * f
        // Keep the anchor at the same relative position inside the frame.
        let rx = (anchor.x - frame.minX) / frame.width
        let ry = (anchor.y - frame.minY) / frame.height
        return CGRect(x: anchor.x - rx * w, y: anchor.y - ry * h, width: w, height: h)
    }

    /// Zoom factor for one scroll-wheel step. Positive delta grows the pin.
    public static func factor(forScrollDelta delta: CGFloat) -> CGFloat {
        let clamped = min(max(delta, -20), 20)
        return CGFloat(pow(1.01, Double(clamped)))
    }
}
