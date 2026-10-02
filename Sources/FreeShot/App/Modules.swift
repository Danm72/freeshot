import AppKit
import CoreGraphics
import FreeShotCore

// Integration points. Each feature agent provides a concrete type in its own directory
// and the integrator assigns it in ModuleRegistry.installDefaults(). Call every entry
// point on the main thread.

/// Capture/ owns this: overlays, window picker, All-in-One HUD, self-timer.
protocol CaptureModule: AnyObject {
    func captureArea()
    func captureFullscreen()
    func captureWindow()
    func allInOne()
    func capturePreviousArea()
    func captureText()
    func startRecording()
}

/// QuickAccess/ owns this: save + copy + Quick Access Overlay after every capture.
protocol PipelineModule: AnyObject {
    func handle(_ result: CaptureResult)
}

/// Annotate/ owns this.
protocol AnnotateModule: AnyObject {
    func open(imageURL: URL)
}

/// Extras/ owns the next four.
protocol PinModule: AnyObject {
    func pin(imageURL: URL)
}

protocol OCRModule: AnyObject {
    func recognize(_ image: CGImage) async -> String
}

protocol RecorderModule: AnyObject {
    var isRecording: Bool { get }
    /// `rect` is in Cocoa global points; nil records the whole display.
    func start(rect: CGRect?, display: CGDirectDisplayID)
    func stop()
}

protocol SettingsUI: AnyObject {
    func show()
}

extension Notification.Name {
    /// Post when recording starts or stops. MenuBarController turns the icon red.
    static let freeShotRecordingStateChanged = Notification.Name("FreeShotRecordingStateChanged")
    /// Post after the pipeline adds a capture to history. MenuBarController refreshes Recent.
    static let freeShotHistoryChanged = Notification.Name("FreeShotHistoryChanged")
    /// Post after hotkeys change in Settings. AppDelegate re-registers them.
    static let freeShotHotkeysChanged = Notification.Name("FreeShotHotkeysChanged")
}

/// The single holder of module instances and shared state.
final class ModuleRegistry {
    static let shared = ModuleRegistry()

    let settings = AppSettings.shared
    let history = CaptureHistory()

    var capture: CaptureModule = StubCapture()
    var pipeline: PipelineModule = StubPipeline()
    var annotate: AnnotateModule = StubAnnotate()
    var pin: PinModule = StubPin()
    var ocr: OCRModule = StubOCR()
    var recorder: RecorderModule = StubRecorder()
    var settingsUI: SettingsUI = StubSettingsUI()

    private init() {}

    /// The integrator replaces stub assignments here with the concrete modules.
    func installDefaults() {}
}
