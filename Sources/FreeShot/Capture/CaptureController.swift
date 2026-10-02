import AppKit
import FreeShotCore

/// The concrete CaptureModule. Install with `ModuleRegistry.shared.capture = CaptureController()`.
///
/// - Area, window, text and record start an overlay over frozen snapshots of every display.
///   A screenshot crops the frozen snapshot, so the pixels match what was on screen at the hotkey.
/// - The area screenshot fires on mouse-up. A click with no drag does nothing, except in
///   record mode, where it records the full display.
/// - Fullscreen grabs the display under the cursor, live.
/// - With the All-in-One self-timer on, the capture runs live after a 5 s countdown.
/// Results go to `ModuleRegistry.shared.pipeline.handle(_:)`.
final class CaptureController: CaptureModule, AreaOverlayDelegate {
    private var registry: ModuleRegistry { .shared }
    private var settings: AppSettings { registry.settings }

    private var session: AreaOverlaySession?
    private var starting = false
    private var previousApp: NSRunningApplication?

    /// True while an overlay is up, a snapshot is being taken or a countdown runs.
    var isBusy: Bool { session != nil || starting || SelfTimer.isRunning }

    // MARK: CaptureModule

    func captureArea() { startSession(purpose: .screenshot, mode: .area, hud: false) }
    func captureWindow() { startSession(purpose: .screenshot, mode: .window, hud: false) }
    func allInOne() { startSession(purpose: .screenshot, mode: .area, hud: true) }
    func captureText() { startSession(purpose: .text, mode: .area, hud: false) }
    func startRecording() { startSession(purpose: .record, mode: .area, hud: false) }

    func captureFullscreen() {
        guard !isBusy, let screen = ScreenCapturer.screenUnderMouse() else { return }
        liveFullscreen(screen)
    }

    func capturePreviousArea() {
        guard !isBusy else { return }
        guard let last = settings.lastArea, let screen = ScreenCapturer.screen(for: last.displayID) else {
            captureArea()
            return
        }
        liveArea(last.cocoaRect, screen: screen)
    }

    // MARK: Session

    private func startSession(purpose: OverlayPurpose, mode: OverlayMode, hud: Bool) {
        if session != nil {
            // The same hotkey again while the overlay is up closes it.
            endSession()
            return
        }
        guard !starting, !SelfTimer.isRunning else { return }
        starting = true
        Task { @MainActor in
            defer { self.starting = false }
            do {
                let snaps = try await ScreenCapturer.snapshotAllDisplays()
                let s = AreaOverlaySession(snapshots: snaps, purpose: purpose, mode: mode, showHUD: hud)
                s.delegate = self
                self.session = s
                let front = NSWorkspace.shared.frontmostApplication
                self.previousApp = (front?.processIdentifier == getpid()) ? nil : front
                NSApp.activate()
                s.show()
            } catch {
                captureLog("snapshot failed: \(error)")
            }
        }
    }

    private func endSession() {
        session?.close()
        session = nil
        // Hand focus back to the app Dan was using.
        if let app = previousApp { app.activate() }
        previousApp = nil
    }

    // MARK: AreaOverlayDelegate

    func overlay(_ o: AreaOverlaySession, didSelectArea rect: CGRect, on snapshot: DisplaySnapshot) {
        let purpose = o.purpose, timed = o.timerArmed
        settings.lastArea = StoredArea(cocoaRect: rect, displayID: snapshot.descriptor.id)
        endSession()
        switch purpose {
        case .screenshot:
            if timed { countdown(on: snapshot.screen) { self.liveArea(rect, screen: snapshot.screen) } }
            else { deliverCrop(of: snapshot, rect: rect) }
        case .text:
            if timed {
                countdown(on: snapshot.screen) {
                    self.liveCrop(rect, screen: snapshot.screen) { img, _ in self.recognize(img) }
                }
            } else if let img = ScreenCapturer.crop(snapshot, cocoaRect: rect) {
                recognize(img)
            }
        case .record:
            let start = { self.registry.recorder.start(rect: rect, display: snapshot.descriptor.id) }
            if timed { countdown(on: snapshot.screen, then: start) } else { start() }
        }
    }

    func overlay(_ o: AreaOverlaySession, didSelectWindow window: PickableWindow, frame: CGRect, on snapshot: DisplaySnapshot) {
        let purpose = o.purpose, timed = o.timerArmed
        endSession()
        switch purpose {
        case .screenshot:
            let go = { self.windowShot(window, frame: frame, fallback: timed ? nil : snapshot) }
            if timed { countdown(on: snapshot.screen, then: go) } else { go() }
        case .text:
            let visible = frame.intersection(snapshot.descriptor.cocoaFrame)
            if let img = ScreenCapturer.crop(snapshot, cocoaRect: visible) { recognize(img) }
        case .record:
            let rect = frame.intersection(snapshot.descriptor.cocoaFrame)
            let start = { self.registry.recorder.start(rect: rect, display: snapshot.descriptor.id) }
            if timed { countdown(on: snapshot.screen, then: start) } else { start() }
        }
    }

    func overlay(_ o: AreaOverlaySession, didClickFullDisplay snapshot: DisplaySnapshot) {
        let timed = o.timerArmed
        endSession()
        let start = { self.registry.recorder.start(rect: nil, display: snapshot.descriptor.id) }
        if timed { countdown(on: snapshot.screen, then: start) } else { start() }
    }

    func overlay(_ o: AreaOverlaySession, didChoose mode: AllInOneMode) {
        switch mode {
        case .area:
            o.purpose = .screenshot
            o.mode = .area
        case .window:
            o.purpose = .screenshot
            o.mode = .window
        case .text:
            o.purpose = .text
            o.mode = .area
        case .record:
            o.purpose = .record
            o.mode = .area
        case .selfTimer:
            o.timerArmed.toggle()
        case .fullscreen:
            guard let snap = o.hudSnapshot else { return }
            let timed = o.timerArmed, purpose = o.purpose
            endSession()
            if purpose == .record {
                let start = { self.registry.recorder.start(rect: nil, display: snap.descriptor.id) }
                if timed { countdown(on: snap.screen, then: start) } else { start() }
            } else if timed {
                countdown(on: snap.screen) { self.liveFullscreen(snap.screen) }
            } else {
                deliver(image: snap.image, scale: snap.scale, rect: snap.descriptor.cocoaFrame, displayID: snap.descriptor.id)
            }
        case .previousArea:
            guard let last = settings.lastArea,
                  let snap = o.snapshots.first(where: { $0.descriptor.id == last.displayID }) else {
                captureLog("no previous area yet")
                return
            }
            let timed = o.timerArmed
            endSession()
            if timed { countdown(on: snap.screen) { self.liveArea(last.cocoaRect, screen: snap.screen) } }
            else { deliverCrop(of: snap, rect: last.cocoaRect) }
        }
    }

    func overlayDidCancel(_ o: AreaOverlaySession) { endSession() }

    // MARK: Captures

    private func countdown(on screen: NSScreen, then work: @escaping () -> Void) {
        SelfTimer.start(on: screen, done: work)
    }

    private func deliverCrop(of snap: DisplaySnapshot, rect: CGRect) {
        guard let img = ScreenCapturer.crop(snap, cocoaRect: rect) else { captureLog("empty selection"); return }
        deliver(image: img, scale: snap.scale, rect: rect, displayID: snap.descriptor.id)
    }

    private func deliver(image: CGImage, scale: CGFloat, rect: CGRect?, displayID: UInt32?) {
        registry.pipeline.handle(CaptureResult(image: image, scale: scale, kind: .screenshot, rect: rect, displayID: displayID))
    }

    private func liveFullscreen(_ screen: NSScreen) {
        Task { @MainActor in
            do {
                let snap = try await ScreenCapturer.captureDisplay(screen)
                self.deliver(image: snap.image, scale: snap.scale, rect: snap.descriptor.cocoaFrame, displayID: snap.descriptor.id)
            } catch {
                captureLog("fullscreen failed: \(error)")
            }
        }
    }

    private func liveCrop(_ rect: CGRect, screen: NSScreen, then use: @escaping (CGImage, CGFloat) -> Void) {
        Task { @MainActor in
            do {
                let snap = try await ScreenCapturer.captureDisplay(screen)
                guard let img = ScreenCapturer.crop(snap, cocoaRect: rect) else { captureLog("empty area"); return }
                use(img, snap.scale)
            } catch {
                captureLog("area capture failed: \(error)")
            }
        }
    }

    private func liveArea(_ rect: CGRect, screen: NSScreen) {
        guard let id = ScreenCapturer.displayID(of: screen) else { return }
        liveCrop(rect, screen: screen) { img, scale in
            self.deliver(image: img, scale: scale, rect: rect, displayID: id)
        }
    }

    /// A window with its shadow (when the setting is on). Falls back to a crop of the
    /// frozen snapshot, or a live display crop after a countdown, when ScreenCaptureKit
    /// returns a different window.
    private func windowShot(_ window: PickableWindow, frame: CGRect, fallback snap: DisplaySnapshot?) {
        let shadow = settings.windowShadow
        Task { @MainActor in
            do {
                if let shot = try await ScreenCapturer.captureWindow(window, shadow: shadow) {
                    let id = ScreenCapturer.coordinateSpace().display(bestFor: frame)?.id
                    self.deliver(image: shot.image, scale: shot.scale, rect: frame, displayID: id)
                    return
                }
                captureLog("window \(window.windowID) came back the wrong size; cropping the screen instead")
            } catch {
                captureLog("window capture failed: \(error); cropping the screen instead")
            }
            if let snap {
                self.deliverCrop(of: snap, rect: frame.intersection(snap.descriptor.cocoaFrame))
            } else if let screen = ScreenCapturer.screen(for: ScreenCapturer.coordinateSpace().display(bestFor: frame)?.id ?? 0) {
                self.liveArea(frame.intersection(screen.frame), screen: screen)
            }
        }
    }

    // MARK: OCR

    /// Hands the crop to the OCR module. OCRModule (Extras/OCRController) copies the text
    /// and shows the toast, so Capture does neither.
    private func recognize(_ image: CGImage) {
        let ocr = registry.ocr
        Task { @MainActor in _ = await ocr.recognize(image) }
    }
}
