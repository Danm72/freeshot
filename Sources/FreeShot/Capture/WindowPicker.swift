import AppKit
import FreeShotCore

/// The window list frozen at hotkey time, front to back, with hit-testing in Cocoa points.
struct WindowPicker {
    let windows: [PickableWindow]
    let space: CoordinateSpace

    init(space: CoordinateSpace, windows: [PickableWindow] = ScreenCapturer.pickableWindows()) {
        self.space = space
        self.windows = windows
    }

    /// The front-most window under a Cocoa global point.
    func window(atCocoa p: CGPoint) -> PickableWindow? {
        WindowHitTest.window(at: space.cgPoint(fromCocoa: p), in: windows)
    }

    func cocoaFrame(of w: PickableWindow) -> CGRect { space.cocoaRect(fromCG: w.cgFrame) }
}
