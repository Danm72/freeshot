import AppKit
import FreeShotCore

/// A big 5-4-3-2-1 countdown in the centre of a display. Calls `done` after the last
/// number, once the countdown window is off screen, so it never shows in the capture.
final class SelfTimer {
    private static var active: SelfTimer?

    private let panel: NSPanel
    private let label: NSTextField
    private var steps: [Int]
    private var timer: Timer?
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
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        steps.removeFirst()
        if let next = steps.first { label.stringValue = "\(next)" } else { finish() }
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        panel.orderOut(nil)
        panel.close()
        Self.active = nil
        // Give the window server a couple of frames to drop the countdown.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [done] in done() }
    }

    private func cancel() {
        timer?.invalidate()
        timer = nil
        panel.orderOut(nil)
        panel.close()
        Self.active = nil
    }
}
