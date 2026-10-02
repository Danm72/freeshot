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
    /// The Settings hotkey recorder posts this while it waits for a key (userInfo["suspended"] = true)
    /// and when it stops (false). AppDelegate unregisters the Carbon hotkeys meanwhile.
    static let freeShotHotkeysSuspend = Notification.Name("FreeShotHotkeysSuspend")
}

/// The single holder of module instances and shared state.
final class ModuleRegistry {
    static let shared = ModuleRegistry()

    let settings = AppSettings.shared
    let history = CaptureHistory()

    // Lazy, not stored: several modules read ModuleRegistry.shared while they initialise,
    // which would recurse into this static initialiser.
    lazy var capture: CaptureModule = CaptureController()
    lazy var pipeline: PipelineModule = QuickAccessPipeline()
    lazy var annotate: AnnotateModule = AnnotateController()
    lazy var pin: PinModule = PinController()
    lazy var ocr: OCRModule = OCRController()
    lazy var recorder: RecorderModule = ScreenRecorder()
    lazy var settingsUI: SettingsUI = SettingsWindowController()

    private init() {}

    /// Creates every module up front. AppDelegate calls this first, before any hotkey or URL.
    func installDefaults() {
        _ = (capture, pipeline, annotate, pin, ocr, recorder, settingsUI)
    }
}
