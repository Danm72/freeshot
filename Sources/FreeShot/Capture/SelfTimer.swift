import AppKit
import Carbon.HIToolbox
import FreeShotCore

/// A big 5-4-3-2-1 countdown in the centre of a display. Calls `done` after the last
/// number, once the countdown window is off screen, so it never shows in the capture.
/// Esc cancels the countdown, also while another app has focus.
final class SelfTimer {
    private static var active: SelfTimer?

    private let panel: NSPanel
    private let label: NSTextField
    private var steps: [Int]
    private var timer: Timer?
    private var escape: EscapeHotkey?
    private let done: () -> Void

    static var isRunning: Bool { active != nil }

    static func start(on screen: NSScreen, seconds: Int = SelfTimerMath.defaultSeconds, done: @escaping () -> Void) {
        active?.cancel()
        let t = SelfTimer(screen: screen, seconds: seconds, done: done)
        active = t
        t.run()
    }

    static func cancelActive() { active?.cancel() }

    private init(screen: NSScreen, seconds: Int, done: @escaping () -> Void) {
        steps = SelfTimerMath.countdown(from: seconds)
        self.done = done
        let side: CGFloat = 160
        let f = screen.frame
        panel = NSPanel(contentRect: CGRect(x: f.midX - side / 2, y: f.midY - side / 2, width: side, height: side),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false

        let box = NSView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.85).cgColor
        box.layer?.cornerRadius = 28
        label = NSTextField(labelWithString: "")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 88, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.frame = CGRect(x: 0, y: (side - 110) / 2, width: side, height: 110)
        box.addSubview(label)
        panel.contentView = box
    }

    private func run() {
        guard let first = steps.first else { finish(); return }
        label.stringValue = "\(first)"
        panel.orderFrontRegardless()
        escape = EscapeHotkey { SelfTimer.cancelActive() }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        steps.removeFirst()
        if let next = steps.first { label.stringValue = "\(next)" } else { finish() }
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        escape?.invalidate()
        escape = nil
        panel.orderOut(nil)
        panel.close()
        Self.active = nil
        // Give the window server a couple of frames to drop the countdown.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [done] in done() }
    }

    private func cancel() {
        timer?.invalidate()
        timer = nil
        escape?.invalidate()
        escape = nil
        panel.orderOut(nil)
        panel.close()
        Self.active = nil
    }
}

/// Esc as a global Carbon hotkey, held only while a countdown runs. The overlay is closed and
/// focus is back in Dan's app by then, so a local key monitor would see nothing.
/// Carbon hotkeys need no Accessibility permission.
private final class EscapeHotkey {
    private static let signature = fourCC("FSEC")

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let onPress: () -> Void

    init(onPress: @escaping () -> Void) {
        self.onPress = onPress
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            let err = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                        nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            guard err == noErr, hkID.signature == EscapeHotkey.signature else { return OSStatus(eventNotHandledErr) }
            let me = Unmanaged<EscapeHotkey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.onPress() }
            return noErr
        }, 1, &spec, userData, &handler)
        if installed != noErr { captureLog("self-timer Esc handler failed: \(installed)") }
        let status = RegisterEventHotKey(UInt32(kVK_Escape), 0, EventHotKeyID(signature: Self.signature, id: 1),
                                         GetApplicationEventTarget(), 0, &ref)
        if status != noErr { captureLog("self-timer Esc hotkey failed: \(status)") }
    }

    func invalidate() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    deinit { invalidate() }
}
