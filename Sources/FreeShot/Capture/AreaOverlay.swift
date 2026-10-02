import AppKit
import Carbon.HIToolbox
import FreeShotCore
import QuartzCore

/// What the selection is for. It decides what happens on mouse-up.
enum OverlayPurpose {
    case screenshot
    case text
    case record
}

enum OverlayMode {
    case area
    case window
}

protocol AreaOverlayDelegate: AnyObject {
    /// An area was dragged. `rect` is Cocoa global points, inside `snapshot`'s display.
    func overlay(_ o: AreaOverlaySession, didSelectArea rect: CGRect, on snapshot: DisplaySnapshot)
    func overlay(_ o: AreaOverlaySession, didSelectWindow window: PickableWindow, frame: CGRect, on snapshot: DisplaySnapshot)
    /// A click with no drag while recording: record the whole display.
    func overlay(_ o: AreaOverlaySession, didClickFullDisplay snapshot: DisplaySnapshot)
    func overlay(_ o: AreaOverlaySession, didChoose mode: AllInOneMode)
    func overlayDidCancel(_ o: AreaOverlaySession)
}

/// One area-selection session: a frozen, dimmed snapshot per display, crosshair, loupe,
/// W×H label, window picking with Space, and the All-in-One HUD when asked for.
final class AreaOverlaySession {
    weak var delegate: AreaOverlayDelegate?

    let snapshots: [DisplaySnapshot]
    let space: CoordinateSpace
    let picker: WindowPicker
    private let settings = AppSettings.shared

    var purpose: OverlayPurpose { didSet { refresh() } }
    var mode: OverlayMode { didSet { hovered = nil; dragStart = nil; selection = nil; updateCursor(); refresh() } }
    /// All-in-One self-timer toggle. The capture runs live after a 5 s countdown.
    var timerArmed = false { didSet { refresh() } }

    private var windows: [OverlayWindow] = []
    private var views: [OverlayView] = []
    private(set) var hud: AllInOneHUD?

    // Drag state, Cocoa global points.
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint = .zero
    private var dragSnapshot: DisplaySnapshot?
    private var spaceHeld = false
    /// Set when Shift goes down during a drag; cleared when it comes up.
    private var axisLock: AxisLock?
    private var lastMouse: CGPoint = .zero
    private var selection: CGRect?
    private var hovered: PickableWindow?
    private var cursor: CGPoint = NSEvent.mouseLocation
    private var finished = false

    init(snapshots: [DisplaySnapshot], purpose: OverlayPurpose, mode: OverlayMode, showHUD: Bool) {
        self.snapshots = snapshots
        self.space = CoordinateSpace(displays: snapshots.map(\.descriptor))
        self.picker = WindowPicker(space: space)
        self.purpose = purpose
        self.mode = mode
        for snap in snapshots {
            let w = OverlayWindow(screen: snap.screen)
            let v = OverlayView(snapshot: snap, session: self)
            w.contentView = v
            windows.append(w)
            views.append(v)
        }
        if showHUD {
            let screen = snapshot(atCocoa: cursor)?.screen ?? snapshots.first?.screen
            if let screen {
                hud = AllInOneHUD(screen: screen) { [weak self] m in
                    guard let self else { return }
                    self.delegate?.overlay(self, didChoose: m)
                }
            }
        }
    }

    // MARK: Show / close

    func show() {
        for w in windows { w.orderFrontRegardless() }
        // Keyboard goes to the window under the cursor.
        let keyIndex = snapshots.firstIndex { $0.descriptor.id == snapshot(atCocoa: cursor)?.descriptor.id } ?? 0
        if windows.indices.contains(keyIndex) {
            windows[keyIndex].makeKeyAndOrderFront(nil)
            windows[keyIndex].makeFirstResponder(views[keyIndex])
        }
        hud?.show()
        mouseMoved(to: NSEvent.mouseLocation)
    }

    func close() {
        guard !finished else { return }
        finished = true
        hud?.close()
        hud = nil
        for w in windows { w.orderOut(nil); w.close() }
        windows.removeAll()
        views.removeAll()
        NSCursor.arrow.set()
    }

    /// Window numbers of everything this session put on screen.
    var windowNumbers: Set<CGWindowID> {
        var s = Set(windows.map { CGWindowID($0.windowNumber) })
        if let h = hud { s.insert(CGWindowID(h.windowNumber)) }
        return s
    }

    func snapshot(atCocoa p: CGPoint) -> DisplaySnapshot? {
        guard let d = space.display(containingCocoa: p) else { return nil }
        return snapshots.first { $0.descriptor.id == d.id }
    }

    /// The snapshot the HUD sits on, else the one under the cursor.
    var hudSnapshot: DisplaySnapshot? {
        if let h = hud, let id = ScreenCapturer.displayID(of: h.targetScreen) {
            return snapshots.first { $0.descriptor.id == id }
        }
        return snapshot(atCocoa: cursor) ?? snapshots.first
    }

    // MARK: Mouse

    func mouseMoved(to p: CGPoint) {
        cursor = p
        if mode == .window { hovered = picker.window(atCocoa: p) }
        updateCursor()
        refresh()
    }

    func mouseDown(at p: CGPoint) {
        cursor = p
        guard mode == .area, let snap = snapshot(atCocoa: p) else { return }
        dragSnapshot = snap
        let start = CaptureGeometry.clamp(p, to: snap.descriptor.cocoaFrame)
        dragStart = start
        dragCurrent = start
        lastMouse = p
        selection = nil
        axisLock = nil
        refresh()
    }

    func mouseDragged(to p: CGPoint, modifiers: NSEvent.ModifierFlags) {
        cursor = p
        guard mode == .area, let snap = dragSnapshot, var start = dragStart else { refresh(); return }
        let bounds = snap.descriptor.cocoaFrame
        let current = CaptureGeometry.clamp(p, to: bounds)
        if spaceHeld, let sel = selection {
            // Space held: move the whole selection, keep its size.
            let delta = CGVector(dx: p.x - lastMouse.x, dy: p.y - lastMouse.y)
            let moved = CaptureGeometry.move(sel, by: delta, within: bounds)
            let real = CGVector(dx: moved.minX - sel.minX, dy: moved.minY - sel.minY)
            start = CGPoint(x: start.x + real.dx, y: start.y + real.dy)
            dragStart = start
            dragCurrent = CGPoint(x: dragCurrent.x + real.dx, y: dragCurrent.y + real.dy)
            axisLock?.shift(by: real)
        } else {
            dragCurrent = current
        }
        lastMouse = p
        recomputeSelection(modifiers: modifiers)
        refresh()
    }

    func mouseUp(at p: CGPoint, modifiers: NSEvent.ModifierFlags) {
        cursor = p
        switch mode {
        case .window:
            guard let w = hovered ?? picker.window(atCocoa: p) else { return }
            let frame = picker.cocoaFrame(of: w)
            guard let snap = snapshotBest(for: frame) else { return }
            delegate?.overlay(self, didSelectWindow: w, frame: frame, on: snap)
        case .area:
            guard let snap = dragSnapshot, dragStart != nil else { return }
            recomputeSelection(modifiers: modifiers)
            let sel = selection ?? .zero
            dragStart = nil
            dragSnapshot = nil
            spaceHeld = false
            axisLock = nil
            if CaptureGeometry.isClick(sel) {
                selection = nil
                if purpose == .record { delegate?.overlay(self, didClickFullDisplay: snap) } else { refresh() }
                return
            }
            // A selection with no whole pixel on one axis cannot be captured. Keep the overlay open.
            if CaptureGeometry.isDegenerate(sel, scale: snap.scale) {
                selection = nil
                refresh()
                return
            }
            delegate?.overlay(self, didSelectArea: sel, on: snap)
        }
    }

    private func snapshotBest(for cocoaRect: CGRect) -> DisplaySnapshot? {
        guard let d = space.display(bestFor: cocoaRect) else { return snapshot(atCocoa: cursor) }
        return snapshots.first { $0.descriptor.id == d.id }
    }

    private func recomputeSelection(modifiers: NSEvent.ModifierFlags) {
        guard let snap = dragSnapshot, let start = dragStart else { return }
        // Shift locks one axis at the size it had when Shift went down (see flagsChanged).
        let end = axisLock?.end(for: dragCurrent) ?? dragCurrent
        let raw = CaptureGeometry.selection(from: start, to: end, fromCenter: modifiers.contains(.option))
        let clipped = raw.intersection(snap.descriptor.cocoaFrame)
        selection = clipped.isNull ? .zero : CaptureGeometry.pixelAligned(clipped, scale: snap.scale)
    }

    // MARK: Keys

    /// Returns true when the key was used.
    func keyDown(_ e: NSEvent) -> Bool {
        let code = Int(e.keyCode)
        if code == kVK_Escape { delegate?.overlayDidCancel(self); return true }
        if code == kVK_Space {
            if dragStart != nil { spaceHeld = true; lastMouse = NSEvent.mouseLocation }
            else if !e.isARepeat { mode = (mode == .area) ? .window : .area }
            return true
        }
        if let arrow = CaptureGeometry.arrow(forKeyCode: e.keyCode) {
            nudgeCursor(by: CaptureGeometry.nudge(arrow, shift: e.modifierFlags.contains(.shift)), modifiers: e.modifierFlags)
            return true
        }
        if hud != nil, !e.isARepeat, let chars = e.charactersIgnoringModifiers,
           e.modifierFlags.intersection([.command, .control, .option]).isEmpty,
           let m = AllInOneMode.from(character: chars) {
            delegate?.overlay(self, didChoose: m)
            return true
        }
        return false
    }

    func keyUp(_ e: NSEvent) {
        if Int(e.keyCode) == kVK_Space { spaceHeld = false }
    }

    func flagsChanged(_ e: NSEvent) {
        guard dragStart != nil else { return }
        let shift = e.modifierFlags.contains(.shift)
        if shift, axisLock == nil {
            axisLock = AxisLock(anchor: dragCurrent)
        } else if !shift, var lock = axisLock {
            // Keep the locked shape when Shift comes up just before mouse-up.
            dragCurrent = lock.end(for: dragCurrent)
            axisLock = nil
        }
        recomputeSelection(modifiers: e.modifierFlags)
        refresh()
    }

    /// Arrow keys move the pointer 1 pt (10 pt with Shift) for exact edges.
    private func nudgeCursor(by d: CGVector, modifiers: NSEvent.ModifierFlags) {
        let from = NSEvent.mouseLocation
        let allBounds = snapshots.map(\.descriptor.cocoaFrame).reduce(CGRect.null) { $0.union($1) }
        var to = CGPoint(x: from.x + d.dx, y: from.y + d.dy)
        if !allBounds.isNull { to = CaptureGeometry.clamp(to, to: allBounds) }
        CGWarpMouseCursorPosition(space.cgPoint(fromCocoa: to))
        CGAssociateMouseAndMouseCursorPosition(1)
        if dragStart != nil {
            // The arrow keys only move the drag corner; Shift here means a 10 pt step, not axis lock.
            mouseDragged(to: to, modifiers: modifiers.subtracting(.shift))
        } else {
            mouseMoved(to: to)
        }
    }

    // MARK: Drawing

    private func updateCursor() {
        (mode == .window ? NSCursor.pointingHand : NSCursor.crosshair).set()
        for w in windows { w.invalidateCursorRects(for: w.contentView!) }
    }

    var currentCursor: NSCursor { mode == .window ? .pointingHand : .crosshair }

    var hintText: String? {
        if mode == .window { return timerArmed ? "Click a window. Self-timer: 5 s" : nil }
        switch purpose {
        case .record: return "Drag to record an area, or click to record the full screen"
        case .text: return "Drag over the text to copy"
        case .screenshot: return timerArmed ? "Drag an area. Self-timer: 5 s" : nil
        }
    }

    func refresh() {
        guard !finished else { return }
        let hoveredFrame = hovered.map { picker.cocoaFrame(of: $0) }
        let state = OverlayView.State(
            mode: mode,
            cursor: cursor,
            selection: selection,
            dragging: dragStart != nil,
            hoveredWindow: hoveredFrame,
            showMagnifier: settings.showMagnifier && mode == .area,
            showCrosshair: settings.showCrosshair && mode == .area && dragStart == nil,
            hint: hintText)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for v in views { v.render(state) }
        CATransaction.commit()
        hud?.update(selected: hudSelection, timerArmed: timerArmed)
    }

    private var hudSelection: AllInOneMode {
        switch purpose {
        case .text: return .text
        case .record: return .record
        case .screenshot: return mode == .window ? .window : .area
        }
    }
}

// MARK: - Window

/// Borderless, above the menu bar, on every Space. A panel so it can take keys.
final class OverlayWindow: NSPanel {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        hidesOnDeactivate = false
        isMovable = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - View

final class OverlayView: NSView {
    struct State {
        var mode: OverlayMode
        var cursor: CGPoint
        var selection: CGRect?
        var dragging: Bool
        var hoveredWindow: CGRect?
        var showMagnifier: Bool
        var showCrosshair: Bool
        var hint: String?
    }

    let snapshot: DisplaySnapshot
    private weak var session: AreaOverlaySession?

    private let imageLayer = CALayer()
    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let windowTint = CAShapeLayer()
    private let crosshair = CAShapeLayer()
    private let magnifier = MagnifierLayer()
    private let sizeLabel = CATextLayer()
    private let hintLabel = CATextLayer()

    private var origin: CGPoint { snapshot.descriptor.cocoaFrame.origin }
    private var localBounds: CGRect { CGRect(origin: .zero, size: snapshot.descriptor.cocoaFrame.size) }

    init(snapshot: DisplaySnapshot, session: AreaOverlaySession) {
        self.snapshot = snapshot
        self.session = session
        super.init(frame: CGRect(origin: .zero, size: snapshot.descriptor.cocoaFrame.size))
        wantsLayer = true
        let root = layer!
        root.backgroundColor = NSColor.black.cgColor
        let scale = snapshot.scale

        imageLayer.frame = localBounds
        imageLayer.contents = snapshot.image
        imageLayer.contentsGravity = .resize
        imageLayer.magnificationFilter = .nearest
        root.addSublayer(imageLayer)

        dimLayer.frame = localBounds
        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.35).cgColor
        root.addSublayer(dimLayer)

        windowTint.frame = localBounds
        windowTint.fillColor = NSColor.systemBlue.withAlphaComponent(0.22).cgColor
        windowTint.strokeColor = NSColor.systemBlue.withAlphaComponent(0.9).cgColor
        windowTint.lineWidth = 2
        root.addSublayer(windowTint)

        borderLayer.frame = localBounds
        borderLayer.fillColor = nil
        borderLayer.strokeColor = NSColor.white.withAlphaComponent(0.95).cgColor
        borderLayer.lineWidth = 1
        borderLayer.contentsScale = scale
        root.addSublayer(borderLayer)

        crosshair.frame = localBounds
        crosshair.strokeColor = NSColor.white.withAlphaComponent(0.55).cgColor
        crosshair.lineWidth = 1 / scale
        crosshair.shadowColor = NSColor.black.cgColor
        crosshair.shadowOpacity = 0.6
        crosshair.shadowRadius = 0.5
        crosshair.shadowOffset = .zero
        root.addSublayer(crosshair)

        for l in [sizeLabel, hintLabel] {
            l.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
            l.foregroundColor = NSColor.white.cgColor
            l.cornerRadius = 6
            l.alignmentMode = .center
            l.contentsScale = scale
            l.isHidden = true
            root.addSublayer(l)
        }
        sizeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        sizeLabel.fontSize = 12
        hintLabel.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        hintLabel.fontSize = 15

        magnifier.isHidden = true
        magnifier.contentsScale = scale
        root.addSublayer(magnifier)

        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate, .mouseEnteredAndExited],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isOpaque: Bool { true }

    private func local(_ r: CGRect) -> CGRect { r.offsetBy(dx: -origin.x, dy: -origin.y) }
    private func local(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - origin.x, y: p.y - origin.y) }

    func render(_ s: State) {
        let mine = snapshot.descriptor.cocoaFrame
        let cursorHere = s.cursor.x >= mine.minX && s.cursor.x <= mine.maxX && s.cursor.y >= mine.minY && s.cursor.y <= mine.maxY

        // Dim everything except the selection or the hovered window.
        let hole: CGRect? = (s.mode == .area ? s.selection : s.hoveredWindow).map { local($0).intersection(localBounds) }
        dimLayer.path = Self.dimPath(bounds: localBounds, hole: hole)

        if s.mode == .area, let sel = s.selection, !local(sel).intersection(localBounds).isNull, !sel.isEmpty {
            let r = local(sel)
            borderLayer.path = CGPath(rect: r.insetBy(dx: -0.5, dy: -0.5), transform: nil)
            let text = SelectionMath.sizeLabel(for: sel, scale: snapshot.scale)
            sizeLabel.string = text
            let w = Self.textWidth(text, font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)) + 16
            sizeLabel.frame = CaptureGeometry.sizeLabelFrame(for: r, labelSize: CGSize(width: w, height: 20), gap: 6, in: localBounds)
            sizeLabel.isHidden = false
        } else {
            borderLayer.path = nil
            sizeLabel.isHidden = true
        }

        if s.mode == .window, let hw = s.hoveredWindow {
            windowTint.path = CGPath(rect: local(hw).insetBy(dx: 1, dy: 1), transform: nil)
        } else {
            windowTint.path = nil
        }

        if s.showCrosshair && cursorHere {
            let c = local(s.cursor)
            let px = (c.x * snapshot.scale).rounded(.down) / snapshot.scale + 0.5 / snapshot.scale
            let py = (c.y * snapshot.scale).rounded(.down) / snapshot.scale + 0.5 / snapshot.scale
            let p = CGMutablePath()
            p.move(to: CGPoint(x: px, y: 0)); p.addLine(to: CGPoint(x: px, y: localBounds.maxY))
            p.move(to: CGPoint(x: 0, y: py)); p.addLine(to: CGPoint(x: localBounds.maxX, y: py))
            crosshair.path = p
        } else {
            crosshair.path = nil
        }

        if s.showMagnifier && cursorHere {
            let c = local(s.cursor)
            let topLeft = CGPoint(x: c.x, y: localBounds.height - c.y)
            magnifier.update(snapshot: snapshot, cursorLocalTopLeft: topLeft)
            magnifier.frame = CaptureGeometry.placeBeside(cursor: c, size: MagnifierLayer.totalSize, offset: 24, in: localBounds)
            magnifier.isHidden = false
        } else {
            magnifier.isHidden = true
        }

        if let hint = s.hint, cursorHere, !s.dragging {
            hintLabel.string = hint
            let w = Self.textWidth(hint, font: NSFont.systemFont(ofSize: 15, weight: .medium)) + 32
            hintLabel.frame = CGRect(x: (localBounds.width - w) / 2, y: localBounds.height * 0.62, width: w, height: 24)
            hintLabel.isHidden = false
        } else {
            hintLabel.isHidden = true
        }
    }

    static func textWidth(_ s: String, font: NSFont) -> CGFloat {
        ceil((s as NSString).size(withAttributes: [.font: font]).width)
    }

    /// The dim area as up to 4 rects around the hole, so it draws the same under any fill rule.
    static func dimPath(bounds b: CGRect, hole: CGRect?) -> CGPath {
        let p = CGMutablePath()
        guard let h = hole, !h.isNull, !h.isEmpty else { p.addRect(b); return p }
        p.addRect(CGRect(x: b.minX, y: h.maxY, width: b.width, height: b.maxY - h.maxY))   // above
        p.addRect(CGRect(x: b.minX, y: b.minY, width: b.width, height: h.minY - b.minY))   // below
        p.addRect(CGRect(x: b.minX, y: h.minY, width: h.minX - b.minX, height: h.height))  // left
        p.addRect(CGRect(x: h.maxX, y: h.minY, width: b.maxX - h.maxX, height: h.height))  // right
        return p
    }

    // MARK: Events

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: session?.currentCursor ?? .crosshair)
    }

    override func cursorUpdate(with event: NSEvent) { (session?.currentCursor ?? .crosshair).set() }

    override func mouseMoved(with event: NSEvent) { session?.mouseMoved(to: NSEvent.mouseLocation) }
    override func mouseEntered(with event: NSEvent) { session?.mouseMoved(to: NSEvent.mouseLocation) }
    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        session?.mouseDown(at: NSEvent.mouseLocation)
    }
    override func mouseDragged(with event: NSEvent) { session?.mouseDragged(to: NSEvent.mouseLocation, modifiers: event.modifierFlags) }
    override func mouseUp(with event: NSEvent) { session?.mouseUp(at: NSEvent.mouseLocation, modifiers: event.modifierFlags) }
    /// Right-click cancels, a fallback if keys do not reach the overlay.
    override func rightMouseDown(with event: NSEvent) { if let s = session { s.delegate?.overlayDidCancel(s) } }

    override func keyDown(with event: NSEvent) {
        // Unused keys are swallowed: passing them on makes the system beep, and sounds are off.
        _ = session?.keyDown(event)
    }
    override func keyUp(with event: NSEvent) { session?.keyUp(event) }
    override func flagsChanged(with event: NSEvent) { session?.flagsChanged(event) }
    override func cancelOperation(_ sender: Any?) { if let s = session { s.delegate?.overlayDidCancel(s) } }
}
