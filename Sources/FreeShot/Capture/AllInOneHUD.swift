import AppKit
import FreeShotCore

/// The All-in-One bar at the bottom centre of a display, above the area overlay.
/// Buttons: Area, Window, Fullscreen, Previous Area, Self-Timer, Capture Text, Record Screen.
final class AllInOneHUD {
    let targetScreen: NSScreen
    private let panel: HUDPanel
    private let bar: HUDBarView

    init(screen: NSScreen, onChoose: @escaping (AllInOneMode) -> Void) {
        targetScreen = screen
        bar = HUDBarView(onChoose: onChoose)
        let size = bar.intrinsicContentSize
        let f = screen.frame
        let origin = CGPoint(x: f.midX - size.width / 2, y: f.minY + 48)
        panel = HUDPanel(contentRect: CGRect(origin: origin, size: size))
        panel.contentView = bar
    }

    var windowNumber: Int { panel.windowNumber }

    /// The bar view, for snapshot checks.
    var barView: NSView { bar }

    func show() { panel.orderFrontRegardless() }

    func close() { panel.orderOut(nil); panel.close() }

    func update(selected: AllInOneMode, timerArmed: Bool) {
        bar.selected = selected
        bar.timerArmed = timerArmed
    }
}

private final class HUDPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        hidesOnDeactivate = false
        isMovable = false
    }

    // The overlay keeps the keyboard; the HUD only takes clicks.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class HUDBarView: NSView {
    private let onChoose: (AllInOneMode) -> Void
    private let buttonSize = CGSize(width: 84, height: 58)
    private let padding: CGFloat = 8
    private var hover: AllInOneMode?

    var selected: AllInOneMode = .area { didSet { if oldValue != selected { needsDisplay = true } } }
    var timerArmed = false { didSet { if oldValue != timerArmed { needsDisplay = true } } }

    init(onChoose: @escaping (AllInOneMode) -> Void) {
        self.onChoose = onChoose
        super.init(frame: .zero)
        setFrameSize(intrinsicContentSize)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: NSSize {
        let n = CGFloat(AllInOneMode.allCases.count)
        // One gap between the capture group and the timer/text/record group.
        return NSSize(width: padding * 2 + buttonSize.width * n + 12, height: buttonSize.height + padding * 2)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func frame(for m: AllInOneMode) -> CGRect {
        let i = CGFloat(m.rawValue - 1)
        let gap: CGFloat = m.rawValue >= AllInOneMode.selfTimer.rawValue ? 12 : 0
        return CGRect(x: padding + i * buttonSize.width + gap, y: padding, width: buttonSize.width, height: buttonSize.height)
    }

    private func mode(at p: CGPoint) -> AllInOneMode? { AllInOneMode.allCases.first { frame(for: $0).contains(p) } }

    override func draw(_ dirtyRect: NSRect) {
        let bg = NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14)
        NSColor(white: 0.1, alpha: 0.92).setFill()
        bg.fill()
        NSColor(white: 1, alpha: 0.12).setStroke()
        bg.lineWidth = 1
        bg.stroke()

        // Divider before the timer group.
        let divX = frame(for: .selfTimer).minX - 6
        NSColor(white: 1, alpha: 0.15).setFill()
        CGRect(x: divX - 0.5, y: padding + 10, width: 1, height: buttonSize.height - 20).fill()

        for m in AllInOneMode.allCases {
            let r = frame(for: m).insetBy(dx: 2, dy: 2)
            let active = (m == selected) || (m == .selfTimer && timerArmed)
            if active || m == hover {
                let fill = active ? NSColor.controlAccentColor.withAlphaComponent(0.85) : NSColor(white: 1, alpha: 0.10)
                fill.setFill()
                NSBezierPath(roundedRect: r, xRadius: 9, yRadius: 9).fill()
            }
            let tint: NSColor = (m == .record && !active) ? .systemRed : .white
            if let img = NSImage(systemSymbolName: m.symbolName, accessibilityDescription: m.title)?
                .withSymbolConfiguration(.init(pointSize: 17, weight: .regular)) {
                let tinted = img.tinted(tint)
                let s = tinted.size
                tinted.draw(in: CGRect(x: r.midX - s.width / 2, y: r.maxY - 8 - s.height, width: s.width, height: s.height))
            }
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            let title = "\(m.title)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.92),
                .paragraphStyle: para,
            ]
            title.draw(in: CGRect(x: r.minX, y: r.minY + 14, width: r.width, height: 14), withAttributes: attrs)
            let keyAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
                .foregroundColor: NSColor.white.withAlphaComponent(0.5),
                .paragraphStyle: para,
            ]
            "\(m.rawValue) · \(m.letter)".draw(in: CGRect(x: r.minX, y: r.minY + 2, width: r.width, height: 12), withAttributes: keyAttrs)
        }
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
    override func cursorUpdate(with event: NSEvent) { NSCursor.arrow.set() }

    override func mouseMoved(with event: NSEvent) {
        let m = mode(at: convert(event.locationInWindow, from: nil))
        if m != hover { hover = m; needsDisplay = true }
        NSCursor.arrow.set()
    }

    override func mouseExited(with event: NSEvent) { hover = nil; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if let m = mode(at: convert(event.locationInWindow, from: nil)) { onChoose(m) }
    }
}

private extension NSImage {
    func tinted(_ color: NSColor) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}
