import AppKit
import CoreGraphics
import FreeShotCore
import ScreenCaptureKit

/// Minimal display grab used by the CLI path and the fullscreen stub.
/// Capture/ owns the full ScreenCapturer; this stays as the headless smoke-test path.
enum DisplayCapture {
    struct Shot {
        let image: CGImage
        let scale: CGFloat
        let displayID: CGDirectDisplayID
        let cocoaFrame: CGRect
    }

    enum Failure: Error, CustomStringConvertible {
        case noScreen
        case displayNotShareable(CGDirectDisplayID)

        var description: String {
            switch self {
            case .noScreen: return "no screen under the mouse"
            case .displayNotShareable(let id): return "display \(id) is not in SCShareableContent"
            }
        }
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Current displays as Core descriptors.
    static func descriptors() -> [DisplayDescriptor] {
        NSScreen.screens.compactMap { s in
            displayID(of: s).map { DisplayDescriptor(id: $0, cocoaFrame: s.frame, scale: s.backingScaleFactor) }
        }
    }

    static func screenUnderMouse() -> NSScreen? {
        let space = CoordinateSpace(displays: descriptors())
        guard let d = space.display(containingCocoa: NSEvent.mouseLocation) else { return NSScreen.main }
        return NSScreen.screens.first { displayID(of: $0) == d.id }
    }

    static func captureDisplayUnderMouse() async throws -> Shot {
        guard let screen = screenUnderMouse(), let id = displayID(of: screen) else { throw Failure.noScreen }
        return try await capture(displayID: id, cocoaFrame: screen.frame, scale: screen.backingScaleFactor)
    }

    static func capture(displayID id: CGDirectDisplayID, cocoaFrame: CGRect, scale: CGFloat) async throws -> Shot {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == id }) else {
            throw Failure.displayNotShareable(id)
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        let pxScale = CGFloat(filter.pointPixelScale)
        config.width = Int((filter.contentRect.width * pxScale).rounded())
        config.height = Int((filter.contentRect.height * pxScale).rounded())
        config.showsCursor = false
        config.captureResolution = .best
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return Shot(image: image, scale: pxScale, displayID: id, cocoaFrame: cocoaFrame)
    }
}
