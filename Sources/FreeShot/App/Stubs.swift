import AppKit
import CoreGraphics
import FreeShotCore

// Placeholder modules. The integrator deletes each stub once its concrete module lands.

private func stubLog(_ what: String) {
    FileHandle.standardError.write("FreeShot: \(what) is not built yet (stub)\n".data(using: .utf8)!)
}

final class StubCapture: CaptureModule {
    func captureArea() { stubLog("area capture") }
    /// Works for real so the shell is usable: grabs the display under the cursor.
    func captureFullscreen() {
        Task { @MainActor in
            do {
                let shot = try await DisplayCapture.captureDisplayUnderMouse()
                ModuleRegistry.shared.pipeline.handle(
                    CaptureResult(image: shot.image, scale: shot.scale, rect: shot.cocoaFrame, displayID: shot.displayID))
            } catch {
                FileHandle.standardError.write("FreeShot: fullscreen capture failed: \(error)\n".data(using: .utf8)!)
            }
        }
    }
    func captureWindow() { stubLog("window capture") }
    func allInOne() { stubLog("All-in-One") }
    func capturePreviousArea() { stubLog("previous area") }
    func captureText() { stubLog("OCR capture") }
    func startRecording() { stubLog("recording") }
}

/// Saves and copies per settings, records history. No overlay.
final class StubPipeline: PipelineModule {
    func handle(_ result: CaptureResult) {
        let reg = ModuleRegistry.shared
        guard let image = result.image else { stubLog("pipeline for recordings"); return }
        var saved: URL?
        if reg.settings.saveAfterCapture {
            let url = FilenameGenerator().uniqueURL(in: reg.settings.saveFolder,
                                                    kind: .screenshot(scale: result.scale), date: result.date)
            do {
                try ImageExport.writePNG(image, to: url, scale: result.scale)
                saved = url
                reg.history.add(HistoryEntry(url: url, date: result.date))
                NotificationCenter.default.post(name: .freeShotHistoryChanged, object: nil)
            } catch {
                FileHandle.standardError.write("FreeShot: save failed: \(error)\n".data(using: .utf8)!)
            }
        }
        if reg.settings.copyAfterCapture { ImageExport.copy(image, scale: result.scale, fileURL: saved) }
    }
}

final class StubAnnotate: AnnotateModule {
    func open(imageURL: URL) { NSWorkspace.shared.open(imageURL) }
}

final class StubPin: PinModule {
    func pin(imageURL: URL) { stubLog("pin") }
}

final class StubOCR: OCRModule {
    func recognize(_ image: CGImage) async -> String { stubLog("OCR"); return "" }
}

final class StubRecorder: RecorderModule {
    var isRecording: Bool { false }
    func start(rect: CGRect?, display: CGDirectDisplayID) { stubLog("recorder") }
    func stop() {}
}

final class StubSettingsUI: SettingsUI {
    func show() { stubLog("settings window") }
}
