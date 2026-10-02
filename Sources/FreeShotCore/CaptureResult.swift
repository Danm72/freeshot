import CoreGraphics
import Foundation

/// What a capture module hands to the after-capture pipeline.
public struct CaptureResult: @unchecked Sendable {
    public enum Kind: Equatable, Sendable {
        case screenshot
        case recording(URL)
    }

    public var image: CGImage?
    public var scale: CGFloat
    public var kind: Kind
    /// The captured rect in Cocoa global points, when known.
    public var rect: CGRect?
    public var displayID: UInt32?
    public var date: Date

    public init(image: CGImage?, scale: CGFloat, kind: Kind = .screenshot,
                rect: CGRect? = nil, displayID: UInt32? = nil, date: Date = Date()) {
        self.image = image
        self.scale = scale
        self.kind = kind
        self.rect = rect
        self.displayID = displayID
        self.date = date
    }
}
