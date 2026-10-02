import AppKit
import AVFoundation
import CoreMedia
import FreeShotCore
import ScreenCaptureKit

/// Screen recording with SCStream + SCRecordingOutput to an H.264 MP4, no audio, cursor shown.
/// Posts .freeShotRecordingStateChanged on start and stop; MenuBarController turns its icon red.
/// When the file is done it goes to the pipeline as CaptureResult(kind: .recording(url)).
final class ScreenRecorder: NSObject, RecorderModule {
    private enum Phase { case idle, starting, recording, stopping }

    private var phase: Phase = .idle
    private var stopRequested = false
    /// True once SCRecordingOutput has taken its first frame. Stopping before that
    /// leaves no file, so a stop waits for it.
    private var outputStarted = false
    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private let sink = NullStreamOutput()
    private let sampleQueue = DispatchQueue(label: "ie.mawla.freeshot.recorder.samples")
    private var outputURL: URL?
    private var started: Date = Date()
    private var geometry: RecordingGeometry?
    private var displayID: CGDirectDisplayID = 0
    private var scale: CGFloat = 2

    /// True from the moment `start` is called until the file is final, so a second
    /// hotkey press during start-up stops the recording rather than starting another.
    var isRecording: Bool { phase != .idle }

    func start(rect: CGRect?, display: CGDirectDisplayID) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard phase == .idle else { return }
        let descriptors = DisplayCapture.descriptors()
        let space = CoordinateSpace(displays: descriptors)
        guard let desc = space.display(id: display) ?? rect.flatMap({ space.display(bestFor: $0) }) ?? space.primary,
              let geo = RecordingGeometry.make(rect: rect, on: desc, space: space) else {
            fail("the area is not on a display")
            return
        }
        phase = .starting
        stopRequested = false
        outputStarted = false
        geometry = geo
        displayID = desc.id
        scale = desc.scale
        notify()
        Task { @MainActor in await self.begin(display: desc, geometry: geo) }
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        switch phase {
        case .idle, .stopping: return
        case .starting: stopRequested = true
        case .recording:
            if outputStarted { finish(); return }
            stopRequested = true
            // Do not stay red for ever if the first frame never comes.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if self.phase == .recording { self.finish() }
            }
        }
    }

    // MARK: Start

    @MainActor
    private func begin(display desc: DisplayDescriptor, geometry geo: RecordingGeometry) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == desc.id }) else {
                throw RecorderError.displayNotShareable
            }
            // Keep FreeShot's own windows (toast, overlay, HUD) out of the video.
            let me = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])

            let config = SCStreamConfiguration()
            config.sourceRect = geo.sourceRect
            config.width = geo.pixelWidth
            config.height = geo.pixelHeight
            let fps = max(1, ModuleRegistry.shared.settings.recordFPS)
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
            config.showsCursor = true
            config.capturesAudio = false
            config.queueDepth = 8
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.colorSpaceName = CGColorSpace.sRGB

            let settings = ModuleRegistry.shared.settings
            let date = Date()
            let url = FilenameGenerator().uniqueURL(in: settings.saveFolder, kind: .recording, date: date)
            try FileManager.default.createDirectory(at: settings.saveFolder, withIntermediateDirectories: true)

            let outConfig = SCRecordingOutputConfiguration()
            outConfig.outputURL = url
            outConfig.outputFileType = .mp4
            outConfig.videoCodecType = .h264
            let output = SCRecordingOutput(configuration: outConfig, delegate: self)

            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            // A screen output keeps ScreenCaptureKit from logging a dropped frame for each sample.
            try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sampleQueue)
            try stream.addRecordingOutput(output)
            if stopRequested {
                // Stopped before capture began: cancel quietly, no file.
                phase = .idle
                notify()
                log("cancelled before start")
                return
            }
            try await stream.startCapture()

            self.stream = stream
            self.recordingOutput = output
            self.outputURL = url
            self.started = date
            phase = .recording
            log("recording to \(url.path)")
            if stopRequested && outputStarted { finish() }
        } catch {
            stream = nil
            recordingOutput = nil
            phase = .idle
            notify()
            fail("\(error.localizedDescription)")
        }
    }

    // MARK: Stop

    private func finish() {
        guard phase == .recording, let stream else { return }
        phase = .stopping
        Task { @MainActor in
            do {
                try await stream.stopCapture()
            } catch {
                log("stopCapture: \(error)")
            }
            // SCRecordingOutput finalises the file when the stream stops; the delegate
            // call below hands it on. Fall back after a short wait if it never comes.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard self.phase == .stopping else { return }
            self.log("no finish callback; handing the file on anyway")
            self.complete()
        }
    }

    /// Runs once, on main, when the file is final.
    private func complete() {
        guard phase == .stopping || phase == .recording else { return }
        let url = outputURL
        let geo = geometry
        if let stream, let recordingOutput { try? stream.removeRecordingOutput(recordingOutput) }
        stream = nil
        recordingOutput = nil
        outputURL = nil
        phase = .idle
        notify()
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            fail("the recording file was not written")
            return
        }
        let registry = ModuleRegistry.shared
        // History de-duplicates by path, so a pipeline that also adds it is harmless.
        registry.history.add(HistoryEntry(url: url, date: started, kind: .recording))
        NotificationCenter.default.post(name: .freeShotHistoryChanged, object: nil)
        registry.pipeline.handle(CaptureResult(image: nil, scale: scale, kind: .recording(url),
                                               rect: geo?.cocoaRect, displayID: displayID, date: started))
    }

    private func notify() {
        NotificationCenter.default.post(name: .freeShotRecordingStateChanged, object: self)
    }

    private func fail(_ why: String) {
        log("failed: \(why)")
        Toast.show("Recording failed: \(why)", symbol: "exclamationmark.triangle.fill", seconds: 3)
    }

    private func log(_ s: String) {
        FileHandle.standardError.write("FreeShot recorder: \(s)\n".data(using: .utf8)!)
    }

    enum RecorderError: LocalizedError {
        case displayNotShareable
        var errorDescription: String? { "the display is not shareable" }
    }
}

extension ScreenRecorder: SCRecordingOutputDelegate {
    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        DispatchQueue.main.async {
            self.outputStarted = true
            if self.stopRequested && self.phase == .recording { self.finish() }
        }
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        DispatchQueue.main.async {
            self.log("recording output error: \(error)")
            if self.phase == .recording { self.finish() }
        }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        DispatchQueue.main.async { self.complete() }
    }
}

extension ScreenRecorder: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        DispatchQueue.main.async {
            self.log("stream stopped: \(error)")
            // The user can stop sharing from the system menu; keep what was recorded.
            if self.phase == .recording {
                self.phase = .stopping
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.complete() }
            }
        }
    }
}

/// Receives screen samples and drops them; SCRecordingOutput writes the file.
private final class NullStreamOutput: NSObject, SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {}
}
