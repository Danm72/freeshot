import CoreGraphics
import Foundation
import ImageIO

/// The 3 points of an arrow head plus where the shaft stops.
public struct ArrowHead: Equatable, Sendable {
    public var tip: CGPoint
    public var left: CGPoint
    public var right: CGPoint
    /// The centre of the head's base. Stroke the shaft to here so its cap stays inside the head.
    public var base: CGPoint
}

/// Pure geometry for the Annotate editor. Units are image pixels, origin top-left.
public enum AnnotateGeometry {
    public static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(b.x - a.x, b.y - a.y) }

    public static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    // MARK: Arrow

    /// Head length for a stroke width: 4.5 × width, at least 12 px, and never more than
    /// 60 % of a short arrow.
    public static func arrowHeadLength(lineWidth: CGFloat, arrowLength: CGFloat) -> CGFloat {
        min(max(12, lineWidth * 4.5), arrowLength * 0.6)
    }

    /// The head of an arrow from `start` to `end`. The head is as wide as it is long.
    public static func arrowHead(start: CGPoint, end: CGPoint, lineWidth: CGFloat) -> ArrowHead {
        let len = distance(start, end)
        guard len > 0 else { return ArrowHead(tip: end, left: end, right: end, base: end) }
        let ux = (end.x - start.x) / len, uy = (end.y - start.y) / len
        let headLen = arrowHeadLength(lineWidth: lineWidth, arrowLength: len)
        let half = headLen * 0.5
        let base = CGPoint(x: end.x - ux * headLen, y: end.y - uy * headLen)
        // Perpendicular (-uy, ux).
        let left = CGPoint(x: base.x - uy * half, y: base.y + ux * half)
        let right = CGPoint(x: base.x + uy * half, y: base.y - ux * half)
        return ArrowHead(tip: end, left: left, right: right, base: base)
    }

    // MARK: Constraints (Shift)

    /// Snaps `end` so the segment from `start` sits on the nearest multiple of 45°.
    public static func snapAngle(start: CGPoint, end: CGPoint, stepDegrees: CGFloat = 45) -> CGPoint {
        let len = distance(start, end)
        guard len > 0 else { return end }
        let step = stepDegrees * .pi / 180
        let angle = atan2(end.y - start.y, end.x - start.x)
        let snapped = (angle / step).rounded() * step
        var p = CGPoint(x: start.x + cos(snapped) * len, y: start.y + sin(snapped) * len)
        // Kill float noise on the axes.
        if abs(p.x - start.x) < 1e-9 { p.x = start.x }
        if abs(p.y - start.y) < 1e-9 { p.y = start.y }
        return p
    }

    /// Moves `end` so the box from `start` is a square, keeping the drag direction.
    public static func squareEnd(start: CGPoint, end: CGPoint) -> CGPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        let side = max(abs(dx), abs(dy))
        return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
    }

    // MARK: Crop

    /// Clamps a crop to the image and snaps it to whole pixels.
    /// Returns nil when less than 1 px is left, or when the crop covers the whole image.
    public static func clampCrop(_ r: CGRect, to imageSize: CGSize) -> CGRect? {
        let bounds = CGRect(origin: .zero, size: imageSize)
        let snapped = CGRect(x: r.standardized.minX.rounded(), y: r.standardized.minY.rounded(),
                             width: r.standardized.width.rounded(), height: r.standardized.height.rounded())
        let clipped = snapped.intersection(bounds)
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { return nil }
        return clipped == bounds ? nil : clipped
    }

    // MARK: Pixelate

    /// Block size in pixels for a CleanShot-style intensity (points) at a display scale.
    public static func pixelateBlockSize(intensity: Double, scale: CGFloat) -> Int {
        max(2, Int((intensity * Double(max(scale, 1))).rounded()))
    }

    /// The blocks that tile `rect` (whole pixels), starting at its top-left corner.
    /// Edge blocks are clipped to the rect, so the blocks cover it exactly once.
    public static func pixelBlocks(in rect: CGRect, block: Int) -> [CGRect] {
        let r = rect.integral
        guard block > 0, r.width > 0, r.height > 0 else { return [] }
        let b = CGFloat(block)
        var out: [CGRect] = []
        var y = r.minY
        while y < r.maxY {
            var x = r.minX
            let h = min(b, r.maxY - y)
            while x < r.maxX {
                out.append(CGRect(x: x, y: y, width: min(b, r.maxX - x), height: h))
                x += b
            }
            y += b
        }
        return out
    }

    // MARK: Counter

    /// Radius of a numbered circle for a stroke width.
    public static func counterRadius(lineWidth: CGFloat) -> CGFloat { max(14, 10 + lineWidth * 2.5) }

    // MARK: Distances for hit testing

    public static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return distance(p, a) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return distance(p, CGPoint(x: a.x + t * dx, y: a.y + t * dy))
    }

    public static func distance(from p: CGPoint, toPolyline pts: [CGPoint]) -> CGFloat {
        guard let first = pts.first else { return .infinity }
        guard pts.count > 1 else { return distance(p, first) }
        var best = CGFloat.infinity
        for i in 1..<pts.count { best = min(best, distance(from: p, toSegment: pts[i - 1], pts[i])) }
        return best
    }

    /// Distance from `p` to the outline of a rect (0 on the edge).
    public static func distance(from p: CGPoint, toRectEdge r: CGRect) -> CGFloat {
        let corners = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                       CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
        return distance(from: p, toPolyline: corners + [corners[0]])
    }

    /// Approximate distance from `p` to the outline of the ellipse inscribed in `r`.
    public static func distance(from p: CGPoint, toEllipseIn r: CGRect) -> CGFloat {
        let a = r.width / 2, b = r.height / 2
        guard a > 0, b > 0 else { return distance(from: p, toSegment: CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY)) }
        let dx = p.x - r.midX, dy = p.y - r.midY
        let k = sqrt((dx * dx) / (a * a) + (dy * dy) / (b * b))
        return abs(k - 1) * min(a, b)
    }

    // MARK: Image scale

    /// The backing scale of a saved capture: DPI / 72 when the file has DPI metadata,
    /// else "@2x" style in the name, else 1.
    public static func imageScale(dpi: Double?, fileName: String) -> CGFloat {
        if let dpi, dpi > 72.5 { return CGFloat((dpi / 72).rounded()) }
        if let r = fileName.range(of: #"@(\d)x"#, options: .regularExpression) {
            let digit = fileName[r].dropFirst().prefix(1)
            if let n = Int(digit), n > 0 { return CGFloat(n) }
        }
        return 1
    }

    public static func imageScale(of url: URL) -> CGFloat {
        var dpi: Double?
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            dpi = (props[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue
        }
        return imageScale(dpi: dpi, fileName: url.lastPathComponent)
    }
}
