import AppKit
import FreeShotCore
import QuartzCore

/// The loupe next to the cursor: a pixel-exact zoom of the frozen snapshot with a grid,
/// a marked centre pixel and the cursor coordinates under it.
final class MagnifierLayer: CALayer {
    static let pixelsAcross = 15
    static let cell: CGFloat = 8
    static var loupeSide: CGFloat { CGFloat(pixelsAcross) * cell }
    static let labelHeight: CGFloat = 20
    static var totalSize: CGSize { CGSize(width: loupeSide, height: loupeSide + labelHeight + 4) }

    private let loupe = CALayer()
    private let zoom = CALayer()
    private let grid = CAShapeLayer()
    private let centre = CAShapeLayer()
    private let label = CATextLayer()

    override init() {
        super.init()
        setup()
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError("not used") }

    private func setup() {
        let side = Self.loupeSide
        frame = CGRect(origin: .zero, size: Self.totalSize)

        loupe.frame = CGRect(x: 0, y: Self.labelHeight + 4, width: side, height: side)
        loupe.backgroundColor = NSColor.black.cgColor
        loupe.cornerRadius = 10
        loupe.masksToBounds = true
        loupe.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        loupe.borderWidth = 2
        addSublayer(loupe)

        zoom.magnificationFilter = .nearest
        zoom.minificationFilter = .nearest
        loupe.addSublayer(zoom)

        let path = CGMutablePath()
        for i in 1..<Self.pixelsAcross {
            let v = CGFloat(i) * Self.cell
            path.move(to: CGPoint(x: v, y: 0)); path.addLine(to: CGPoint(x: v, y: side))
            path.move(to: CGPoint(x: 0, y: v)); path.addLine(to: CGPoint(x: side, y: v))
        }
        grid.path = path
        grid.frame = loupe.bounds
        grid.strokeColor = NSColor.black.withAlphaComponent(0.18).cgColor
        grid.lineWidth = 0.5
        grid.fillColor = nil
        loupe.addSublayer(grid)

        let mid = CGFloat(Self.pixelsAcross / 2) * Self.cell
        centre.path = CGPath(rect: CGRect(x: mid, y: mid, width: Self.cell, height: Self.cell), transform: nil)
        centre.frame = loupe.bounds
        centre.strokeColor = NSColor.white.cgColor
        centre.fillColor = nil
        centre.lineWidth = 1.5
        centre.shadowColor = NSColor.black.cgColor
        centre.shadowOpacity = 0.8
        centre.shadowRadius = 1
        centre.shadowOffset = .zero
        loupe.addSublayer(centre)

        label.frame = CGRect(x: 0, y: 0, width: side, height: Self.labelHeight)
        label.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        label.cornerRadius = 5
        label.foregroundColor = NSColor.white.cgColor
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.fontSize = 11
        label.alignmentMode = .center
        addSublayer(label)
    }

    /// Shows the pixels around `cursorLocalTopLeft` (display-local top-left points).
    func update(snapshot: DisplaySnapshot, cursorLocalTopLeft p: CGPoint) {
        let n = Self.pixelsAcross
        let src = CaptureGeometry.magnifierSourcePixels(cursorLocalTopLeft: p, scale: snapshot.scale, pixelsAcross: n)
        let imageBounds = CGRect(x: 0, y: 0, width: snapshot.image.width, height: snapshot.image.height)
        let clipped = src.intersection(imageBounds)
        if clipped.isNull || clipped.isEmpty {
            zoom.contents = nil
        } else {
            zoom.contents = snapshot.image.cropping(to: clipped)
            let c = Self.cell, side = Self.loupeSide
            let top = (clipped.minY - src.minY) * c
            zoom.frame = CGRect(x: (clipped.minX - src.minX) * c,
                                y: side - top - clipped.height * c,
                                width: clipped.width * c, height: clipped.height * c)
        }
        label.string = CaptureGeometry.coordinateLabel(cursorLocalTopLeft: p)
        label.contentsScale = snapshot.scale
    }
}
