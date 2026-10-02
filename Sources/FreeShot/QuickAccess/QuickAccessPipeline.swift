import AppKit
import AVFoundation
import FreeShotCore

/// The concrete after-capture pipeline: save, copy, record history, show Quick Access.
/// Integrator: `ModuleRegistry.shared.pipeline = QuickAccessPipeline()`.
final class QuickAccessPipeline: PipelineModule {
    private var registry: ModuleRegistry { .shared }
    private let ioQueue = DispatchQueue(label: "ie.mawla.freeshot.pipeline", qos: .userInitiated)
    /// Target paths of captures whose file is not on disk yet. Main thread only.
    /// Two captures in the same second would otherwise get the same name and overwrite each other.
    private var reserved = Set<URL>()

    func handle(_ result: CaptureResult) {
        dispatchPrecondition(condition: .onQueue(.main))
        let settings = registry.settings
        let options = CapturePlan.Options(save: settings.saveAfterCapture, copy: settings.copyAfterCapture,
                                          overlay: settings.showOverlayAfterCapture,
                                          saveFolder: settings.saveFolder, tempFolder: CapturePlan.defaultTempFolder)
        let plan = CapturePlan.make(kind: result.kind, scale: result.scale, date: result.date, options: options,
                                    exists: CapturePlan.existsCheck(reserved: reserved))
        if let url = plan.fileURL { reserved.insert(url.standardizedFileURL) }
        if settings.soundsEnabled { Self.playCaptureSound() }

        switch result.kind {
        case .screenshot:
            guard let image = result.image else {
                Self.log("screenshot result has no image")
                if let url = plan.fileURL { reserved.remove(url.standardizedFileURL) }
                return
            }
            // PNG encoding is slow for a full Retina display; keep it off the main thread.
            ioQueue.async {
                var written: URL?
                if let url = plan.fileURL {
                    do {
                        try ImageExport.writePNG(image, to: url, scale: result.scale)
                        written = url
                    } catch {
                        Self.log("save failed: \(error)")
                    }
                }
                DispatchQueue.main.async {
                    self.finish(plan: plan, image: image, scale: result.scale, file: written,
                                kind: .screenshot, result: result)
                }
            }
        case .recording(let source):
            Task.detached(priority: .userInitiated) {
                var file: URL? = source
                if let from = plan.moveFrom, let to = plan.fileURL {
                    do {
                        try FileManager.default.createDirectory(at: to.deletingLastPathComponent(),
                                                                withIntermediateDirectories: true)
                        try FileManager.default.moveItem(at: from, to: to)
                        file = to
                    } catch {
                        Self.log("could not move recording to \(to.path): \(error)")
                    }
                }
                let finalFile = file
                let thumb: CGImage? = if let finalFile { await Self.videoThumbnail(finalFile) } else { nil }
                await MainActor.run {
                    self.finish(plan: plan, image: thumb, scale: 2, file: finalFile, kind: .recording, result: result)
                }
            }
        }
    }

    private func finish(plan: CapturePlan, image: CGImage?, scale: CGFloat, file: URL?,
                        kind: HistoryEntry.Kind, result: CaptureResult) {
        // Release the name whether or not the write worked; a written file now blocks it on disk.
        if let url = plan.fileURL { reserved.remove(url.standardizedFileURL) }
        if plan.addToHistory, let file, !plan.isTemporary {
            registry.history.add(HistoryEntry(url: file, date: result.date, kind: kind))
            NotificationCenter.default.post(name: .freeShotHistoryChanged, object: nil)
        }
        switch plan.copy {
        case .none: break
        case .image:
            if let image { ImageExport.copy(image, scale: scale, fileURL: plan.isTemporary ? nil : file) }
        case .fileURL:
            if let file { ImageExport.copyFile(file) }
        }
        guard plan.showOverlay, let file else { return }
        let item = QuickAccessItem(fileURL: file, image: image, scale: scale,
                                   isRecording: kind == .recording, isTemporary: plan.isTemporary)
        QuickAccessController.shared.show(item, displayID: result.displayID.map { CGDirectDisplayID($0) })
    }

    // MARK: Helpers

    static func videoThumbnail(_ url: URL) async -> CGImage? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 960, height: 960)
        return try? await gen.image(at: .zero).image
    }

    private static func playCaptureSound() {
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        let sound = FileManager.default.fileExists(atPath: path)
            ? NSSound(contentsOfFile: path, byReference: true) : NSSound(named: "Tink")
        sound?.play()
    }

    static func log(_ message: String) {
        FileHandle.standardError.write("FreeShot: \(message)\n".data(using: .utf8)!)
    }
}
