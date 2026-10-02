import CoreGraphics
import Foundation

/// Where Quick Access cards sit on a display. Cocoa coordinates (bottom-left origin).
/// Card 0 is the newest and sits nearest the corner; older cards stack upward.
public struct QuickAccessLayout: Equatable, Sendable {
    public var corner: OverlayCorner
    public var margin: CGFloat
    public var spacing: CGFloat

    public init(corner: OverlayCorner = .bottomLeft, margin: CGFloat = 20, spacing: CGFloat = 12) {
        self.corner = corner
        self.margin = margin
        self.spacing = spacing
    }

    /// "Medium" card size: the image fits in `maxSize`, with a minimum so tiny crops stay clickable.
    public static func cardSize(forImagePoints image: CGSize,
                                maxSize: CGSize = CGSize(width: 240, height: 170),
                                minSize: CGSize = CGSize(width: 150, height: 96)) -> CGSize {
        guard image.width > 0, image.height > 0 else { return maxSize }
        let fit = min(maxSize.width / image.width, maxSize.height / image.height)
        let w = (image.width * fit).rounded()
        let h = (image.height * fit).rounded()
        return CGSize(width: max(w, minSize.width), height: max(h, minSize.height))
    }

    /// Frames for cards of the given sizes, newest first. Cards that would leave the top of
    /// `visibleFrame` get no frame (nil), so the caller closes them.
    public func frames(for sizes: [CGSize], in visibleFrame: CGRect) -> [CGRect?] {
        var y = visibleFrame.minY + margin
        var out: [CGRect?] = []
        for size in sizes {
            let x: CGFloat
            switch corner {
            case .bottomLeft: x = visibleFrame.minX + margin
            case .bottomRight: x = visibleFrame.maxX - margin - size.width
            }
            let frame = CGRect(x: x, y: y, width: size.width, height: size.height)
            if frame.maxY > visibleFrame.maxY - margin && !out.isEmpty {
                out.append(nil)
            } else {
                out.append(frame)
            }
            y += size.height + spacing
        }
        return out
    }
}
