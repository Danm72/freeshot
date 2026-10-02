import AppKit
import CoreGraphics
import FreeShotCore
import ScreenCaptureKit

/// One display frozen at hotkey time, at native pixel resolution.
struct DisplaySnapshot {
    let descriptor: DisplayDescriptor
    let screen: NSScreen
    let image: CGImage
    /// Pixels per point of `image` (2 on Retina).
    let scale: CGFloat
}

/// ScreenCaptureKit wrappers. Every capture is at the display's native pixel size.
enum ScreenCapturer {

    enum Failure: Error, CustomStringConvertible {
        case noDisplays
        case displayGone(UInt32)
        case windowGone(UInt32)
        case emptyCrop

        var description: String {
            switch self {
            case .noDisplays: return "no displays to capture"
            case .displayGone(let id): return "display \(id) is not shareable"
            case .windowGone(let id): return "window \(id) is not shareable"
            case .emptyCrop: return "the selection is empty"
            }
        }
    }

    // MARK: Displays

    static func displayID(of screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func descriptor(of screen: NSScreen) -> DisplayDescriptor? {
        displayID(of: screen).map { DisplayDescriptor(id: $0, cocoaFrame: screen.frame, scale: screen.backingScaleFactor) }
    }

    static func coordinateSpace() -> CoordinateSpace {
        CoordinateSpace(displays: NSScreen.screens.compactMap(descriptor(of:)))
    }

    static func screen(for id: UInt32) -> NSScreen? {
        NSScreen.screens.first { displayID(of: $0) == id }
    }

    static func screenUnderMouse() -> NSScreen? {
        let p = NSEvent.mouseLocation
        guard let d = coordinateSpace().display(containingCocoa: p) else { return NSScreen.main ?? NSScreen.screens.first }
        return screen(for: d.id)
    }

    static func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    /// A live grab of one whole display, without FreeShot's own windows.
    /// `excluding` lists window numbers to leave out when FreeShot is not in the shareable list.
    static func captureDisplay(_ screen: NSScreen, content given: SCShareableContent? = nil,
                               excluding: Set<CGWindowID> = []) async throws -> DisplaySnapshot {
        guard let desc = descriptor(of: screen) else { throw Failure.noDisplays }
        let content: SCShareableContent
        if let given { content = given } else { content = try await shareableContent() }
        guard let display = content.displays.first(where: { $0.displayID == desc.id }) else {
            throw Failure.displayGone(desc.id)
        }
        // FreeShot's own windows (Quick Access cards, pins, toasts) never show in a capture.
        let filter: SCContentFilter
        if let own = content.applications.first(where: { $0.processID == getpid() }) {
            filter = SCContentFilter(display: display, excludingApplications: [own], exceptingWindows: [])
        } else {
            let skip = content.windows.filter { excluding.contains($0.windowID) }
            filter = SCContentFilter(display: display, excludingWindows: skip)
        }
        let config = SCStreamConfiguration()
        let pxScale = CGFloat(filter.pointPixelScale)
        config.width = Int((filter.contentRect.width * pxScale).rounded())
        config.height = Int((filter.contentRect.height * pxScale).rounded())
        config.showsCursor = false
        config.captureResolution = .best
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        // The real pixel ratio comes from the image, in case the system scaled it.
        let scale = CGFloat(image.width) / max(1, desc.cocoaFrame.width)
        return DisplaySnapshot(descriptor: DisplayDescriptor(id: desc.id, cocoaFrame: desc.cocoaFrame, scale: scale),
                               screen: screen, image: image, scale: scale)
    }

    /// Freezes every display at once (the area overlay draws these).
    static func snapshotAllDisplays() async throws -> [DisplaySnapshot] {
        let content = try await shareableContent()
        let screens = NSScreen.screens
        guard !screens.isEmpty else { throw Failure.noDisplays }
        return try await withThrowingTaskGroup(of: (Int, DisplaySnapshot).self) { group in
            for (i, s) in screens.enumerated() {
                group.addTask { @MainActor in (i, try await captureDisplay(s, content: content)) }
            }
            var out: [(Int, DisplaySnapshot)] = []
            for try await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    // MARK: Crops

    /// Crops a Cocoa global rect out of a display snapshot at native pixels.
    static func crop(_ snap: DisplaySnapshot, cocoaRect: CGRect) -> CGImage? {
        let space = CoordinateSpace(displays: [snap.descriptor])
        let px = space.localPixels(fromCocoa: cocoaRect, on: snap.descriptor)
        guard px.width >= 1, px.height >= 1 else { return nil }
        return snap.image.cropping(to: px)
    }

    // MARK: Windows

    /// On-screen windows, front to back, that the picker may offer.
    static func pickableWindows() -> [PickableWindow] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] ?? []
        let all = raw.compactMap(PickableWindow.init(cgInfo:))
        return WindowHitTest.pickable(all, excludingPID: getpid())
    }

    /// A live grab of one window, independent of what covers it.
    /// With `shadow`, macOS 26 adds the system shadow and sizes the image to fit it.
    /// Returns nil when the result does not match the window's size (ScreenCaptureKit can
    /// return a parent window for a child sheet); the caller then crops the frozen snapshot.
    static func captureWindow(_ window: PickableWindow, shadow: Bool) async throws -> (image: CGImage, scale: CGFloat)? {
        let content = try await shareableContent()
        guard let scWindow = content.windows.first(where: { $0.windowID == window.windowID }) else {
            throw Failure.windowGone(window.windowID)
        }
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let scale = CGFloat(filter.pointPixelScale)
        let image: CGImage?
        if #available(macOS 26.0, *) {
            let config = SCScreenshotConfiguration()
            config.ignoreShadows = !shadow
            config.showsCursor = false
            let out = try await SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: config)
            image = out.sdrImage
        } else {
            // macOS 15: the legacy API squeezes a shadow into the frame size, so no shadow here.
            let config = SCStreamConfiguration()
            config.ignoreShadowsSingleWindow = true
            config.showsCursor = false
            config.captureResolution = .best
            config.width = Int((filter.contentRect.width * scale).rounded())
            config.height = Int((filter.contentRect.height * scale).rounded())
            image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        }
        guard let image,
              WindowHitTest.captureSizeFits(pixelSize: CGSize(width: image.width, height: image.height),
                                            frame: window.cgFrame.size, scale: scale)
        else { return nil }
        return (image, scale)
    }
}

/// Writes one line to stderr with the FreeShot prefix.
func captureLog(_ message: String) {
    FileHandle.standardError.write("FreeShot capture: \(message)\n".data(using: .utf8)!)
}
