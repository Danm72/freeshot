import AppKit
import CoreGraphics
import CoreImage
import Foundation

/// Caches pixelate and blur patches so the editor does not recompute them on every redraw.
public final class AnnotationEffectCache {
    private var store: [UUID: (key: String, image: CGImage)] = [:]
    public init() {}

    func image(for a: Annotation, key: String, make: () -> CGImage?) -> CGImage? {
        if let hit = store[a.id], hit.key == key { return hit.image }
        guard let img = make() else { return nil }
        store[a.id] = (key, img)
        return img
    }

    public func removeAll() { store.removeAll() }
}

/// Draws annotations with Core Graphics. Every call expects a context whose user space is
/// image pixels with the origin top-left, y down (see `flipToTopLeft`).
public enum AnnotationRenderer {
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    // MARK: Flatten

    /// The image with every annotation burnt in, cropped to `crop` when set.
    public static func flatten(image: CGImage, annotations: [Annotation], crop: CGRect? = nil) -> CGImage? {
        let w = image.width, h = image.height
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        flipToTopLeft(ctx, height: CGFloat(h))
        for a in annotations { draw(a, in: ctx, source: image) }
        guard let out = ctx.makeImage() else { return nil }
        if let crop, let clamped = AnnotateGeometry.clampCrop(crop, to: CGSize(width: w, height: h)) {
            return out.cropping(to: clamped)
        }
        return out
    }

    /// Turns a bottom-left CG context into a top-left one of the given height.
    public static func flipToTopLeft(_ ctx: CGContext, height: CGFloat) {
        ctx.translateBy(x: 0, y: height)
        ctx.scaleBy(x: 1, y: -1)
    }

    /// Draws a CGImage upright into `rect` of a top-left context.
    public static func drawImage(_ image: CGImage, in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    // MARK: One annotation

    public static func draw(_ a: Annotation, in ctx: CGContext, source: CGImage, cache: AnnotationEffectCache? = nil) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setStrokeColor(a.color.cgColor)
        ctx.setFillColor(a.color.cgColor)
        ctx.setLineWidth(a.lineWidth)

        switch a.kind {
        case .line:
            ctx.move(to: a.start); ctx.addLine(to: a.end); ctx.strokePath()

        case .arrow:
            let head = AnnotateGeometry.arrowHead(start: a.start, end: a.end, lineWidth: a.lineWidth)
            ctx.move(to: a.start); ctx.addLine(to: head.base); ctx.strokePath()
            ctx.setLineWidth(max(1, a.lineWidth * 0.5))
            ctx.move(to: head.tip); ctx.addLine(to: head.left); ctx.addLine(to: head.right); ctx.closePath()
            ctx.drawPath(using: .fillStroke)

        case .rectangle:
            let r = a.rect
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: min(a.lineWidth, r.width / 2),
                               cornerHeight: min(a.lineWidth, r.height / 2), transform: nil))
            ctx.strokePath()

        case .filledRectangle:
            let r = a.rect
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: min(a.lineWidth, r.width / 2),
                               cornerHeight: min(a.lineWidth, r.height / 2), transform: nil))
            ctx.fillPath()

        case .ellipse:
            ctx.strokeEllipse(in: a.rect)

        case .pen:
            strokeFreehand(a.points, in: ctx)

        case .highlighter:
            ctx.setStrokeColor(a.color.withAlpha(0.4).cgColor)
            ctx.setLineWidth(highlighterWidth(a.lineWidth))
            ctx.setLineCap(.square)
            ctx.setBlendMode(.multiply)
            strokeFreehand(a.points, in: ctx)

        case .text:
            drawText(a, in: ctx)

        case .counter:
            drawCounter(a, in: ctx)

        case .pixelate, .blur:
            let r = a.rect.integral.intersection(CGRect(x: 0, y: 0, width: source.width, height: source.height))
            guard !r.isNull, r.width >= 1, r.height >= 1 else { return }
            let key = "\(a.kind.rawValue) \(r) \(a.intensity)"
            let make = { a.kind == .pixelate ? pixelate(source, rect: r, block: Int(a.intensity.rounded()))
                                             : blur(source, rect: r, radius: a.intensity) }
            let patch = cache.map { $0.image(for: a, key: key, make: make) } ?? make()
            if let patch { drawImage(patch, in: r, ctx: ctx) }
        }
    }

    public static func highlighterWidth(_ lineWidth: CGFloat) -> CGFloat { max(16, lineWidth * 4) }

    private static func strokeFreehand(_ pts: [CGPoint], in ctx: CGContext) {
        guard let first = pts.first else { return }
        ctx.move(to: first)
        if pts.count == 1 { ctx.addLine(to: first) }
        // Midpoint quadratic smoothing.
        if pts.count > 2 {
            for i in 1..<(pts.count - 1) {
                let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2, y: (pts[i].y + pts[i + 1].y) / 2)
                ctx.addQuadCurve(to: mid, control: pts[i])
            }
        }
        if pts.count > 1 { ctx.addLine(to: pts[pts.count - 1]) }
        ctx.strokePath()
    }

    // MARK: Text

    public static func textAttributes(_ a: Annotation) -> [NSAttributedString.Key: Any] {
        let font = NSFont.systemFont(ofSize: a.fontSize, weight: .semibold)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(cgColor: a.color.contrastingText.withAlpha(0.35).cgColor)
        shadow.shadowBlurRadius = max(1, a.fontSize / 15)
        shadow.shadowOffset = .zero
        return [.font: font, .foregroundColor: NSColor(cgColor: a.color.cgColor) ?? .red, .shadow: shadow]
    }

    /// The text box in image pixels, with its top-left at the first point.
    public static func textBounds(_ a: Annotation) -> CGRect {
        let s = a.text.isEmpty ? " " : a.text
        let size = (s as NSString).size(withAttributes: textAttributes(a))
        return CGRect(origin: a.start, size: CGSize(width: ceil(size.width), height: ceil(size.height)))
    }

    private static func drawText(_ a: Annotation, in ctx: CGContext) {
        guard !a.text.isEmpty else { return }
        withAppKit(ctx) { (a.text as NSString).draw(at: a.start, withAttributes: textAttributes(a)) }
    }

    private static func drawCounter(_ a: Annotation, in ctx: CGContext) {
        let radius = AnnotateGeometry.counterRadius(lineWidth: a.lineWidth)
        let c = a.start
        let circle = CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)
        ctx.setShadow(offset: .zero, blur: radius * 0.3, color: CGColor(gray: 0, alpha: 0.35))
        ctx.fillEllipse(in: circle)
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        let label = "\(a.number)" as NSString
        let font = NSFont.monospacedDigitSystemFont(ofSize: radius * (label.length > 1 ? 0.95 : 1.15), weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font,
                                                     .foregroundColor: NSColor(cgColor: a.color.contrastingText.cgColor) ?? .white]
        let size = label.size(withAttributes: attrs)
        withAppKit(ctx) {
            label.draw(at: CGPoint(x: c.x - size.width / 2, y: c.y - size.height / 2), withAttributes: attrs)
        }
    }

    /// Runs AppKit string drawing on a top-left CG context.
    private static func withAppKit(_ ctx: CGContext, _ body: () -> Void) {
        let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        body()
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: Effects

    /// Each block of `rect` filled with the block's average colour. `rect` is in top-left pixels.
    public static func pixelate(_ source: CGImage, rect: CGRect, block: Int) -> CGImage? {
        guard let region = source.cropping(to: rect) else { return nil }
        let w = region.width, h = region.height
        guard w > 0, h > 0 else { return nil }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return nil }
        ctx.draw(region, in: CGRect(x: 0, y: 0, width: w, height: h))
        let buf = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        // The bitmap's rows run top to bottom in memory, which matches top-left block math.
        for b in AnnotateGeometry.pixelBlocks(in: CGRect(x: 0, y: 0, width: w, height: h), block: max(1, block)) {
            let x0 = Int(b.minX), y0 = Int(b.minY), x1 = Int(b.maxX), y1 = Int(b.maxY)
            var sum = (0, 0, 0, 0)
            for y in y0..<y1 {
                var i = (y * w + x0) * 4
                for _ in x0..<x1 {
                    sum.0 += Int(buf[i]); sum.1 += Int(buf[i + 1]); sum.2 += Int(buf[i + 2]); sum.3 += Int(buf[i + 3])
                    i += 4
                }
            }
            let n = (x1 - x0) * (y1 - y0)
            let avg = (UInt8(sum.0 / n), UInt8(sum.1 / n), UInt8(sum.2 / n), UInt8(sum.3 / n))
            for y in y0..<y1 {
                var i = (y * w + x0) * 4
                for _ in x0..<x1 {
                    buf[i] = avg.0; buf[i + 1] = avg.1; buf[i + 2] = avg.2; buf[i + 3] = avg.3
                    i += 4
                }
            }
        }
        return ctx.makeImage()
    }

    /// A Gaussian blur of `rect` (top-left pixels) that does not fade at the edges.
    public static func blur(_ source: CGImage, rect: CGRect, radius: CGFloat) -> CGImage? {
        guard let region = source.cropping(to: rect) else { return nil }
        let input = CIImage(cgImage: region)
        let out = input.clampedToExtent().applyingGaussianBlur(sigma: Double(max(1, radius))).cropped(to: input.extent)
        return ciContext.createCGImage(out, from: input.extent)
    }
}

/// Hit testing and bounds for selection.
public enum AnnotationHitTest {
    public static func hits(_ a: Annotation, point p: CGPoint, tolerance: CGFloat) -> Bool {
        let t = tolerance + a.lineWidth / 2
        switch a.kind {
        case .line, .arrow:
            return AnnotateGeometry.distance(from: p, toSegment: a.start, a.end) <= t
        case .rectangle:
            return AnnotateGeometry.distance(from: p, toRectEdge: a.rect) <= t
        case .ellipse:
            return AnnotateGeometry.distance(from: p, toEllipseIn: a.rect) <= t
        case .filledRectangle, .pixelate, .blur:
            return a.rect.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
        case .pen:
            return AnnotateGeometry.distance(from: p, toPolyline: a.points) <= t
        case .highlighter:
            return AnnotateGeometry.distance(from: p, toPolyline: a.points)
                <= tolerance + AnnotationRenderer.highlighterWidth(a.lineWidth) / 2
        case .text:
            return AnnotationRenderer.textBounds(a).insetBy(dx: -tolerance, dy: -tolerance).contains(p)
        case .counter:
            return AnnotateGeometry.distance(p, a.start) <= AnnotateGeometry.counterRadius(lineWidth: a.lineWidth) + tolerance
        }
    }

    /// The box to outline when the annotation is selected.
    public static func bounds(_ a: Annotation) -> CGRect {
        switch a.kind {
        case .text: return AnnotationRenderer.textBounds(a)
        case .counter:
            let r = AnnotateGeometry.counterRadius(lineWidth: a.lineWidth)
            return CGRect(x: a.start.x - r, y: a.start.y - r, width: r * 2, height: r * 2)
        case .pen, .highlighter:
            let xs = a.points.map(\.x), ys = a.points.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return .zero }
            let pad = a.kind == .highlighter ? AnnotationRenderer.highlighterWidth(a.lineWidth) / 2 : a.lineWidth / 2
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -pad, dy: -pad)
        default:
            return a.rect.insetBy(dx: -a.lineWidth / 2, dy: -a.lineWidth / 2)
        }
    }
}
