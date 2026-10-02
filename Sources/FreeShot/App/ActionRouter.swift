import AppKit
import FreeShotCore

/// The one place that maps a FreeShotAction to a module call.
/// Hotkeys, the menu, the URL scheme and the HUD all come through here.
final class ActionRouter {
    static let shared = ActionRouter()

    private var registry: ModuleRegistry { .shared }

    func perform(_ action: FreeShotAction) {
        dispatchPrecondition(condition: .onQueue(.main))
        // While a recording runs, the record or All-in-One hotkey stops it.
        if registry.recorder.isRecording, action == .record || action == .allInOne {
            registry.recorder.stop()
            return
        }
        let capture = registry.capture
        switch action {
        case .fullscreen: capture.captureFullscreen()
        case .area: capture.captureArea()
        case .window: capture.captureWindow()
        case .allInOne: capture.allInOne()
        case .previousArea: capture.capturePreviousArea()
        case .ocr: capture.captureText()
        case .record: capture.startRecording()
        }
    }

    /// freeshot://capture/<action>. Returns false for a URL it does not know.
    @discardableResult
    func handle(url: URL) -> Bool {
        guard let action = FreeShotAction.from(url: url) else {
            FileHandle.standardError.write("FreeShot: unknown URL \(url.absoluteString)\n".data(using: .utf8)!)
            return false
        }
        perform(action)
        return true
    }

    func stopRecording() { registry.recorder.stop() }
    func showSettings() { registry.settingsUI.show() }
    func annotate(_ url: URL) { registry.annotate.open(imageURL: url) }
    func pin(_ url: URL) { registry.pin.pin(imageURL: url) }
}
