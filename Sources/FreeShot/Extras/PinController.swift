import AppKit
import FreeShotCore

/// Keeps every open pin window alive until it closes.
final class PinController: PinModule {
    private var pins: [PinWindow] = []

    func pin(imageURL: URL) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let image = NSImage(contentsOf: imageURL), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            Toast.show("Cannot open the image to pin", symbol: "exclamationmark.triangle.fill")
            return
        }
        // Point size from the file DPI (a @2x PNG at 144 dpi shows at half its pixel size).
        var pointSize = image.size
        if pointSize.width <= 0 || pointSize.height <= 0 { pointSize = NSSize(width: cg.width, height: cg.height) }
        let screen = DisplayCapture.screenUnderMouse() ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let frame = PinGeometry.initialFrame(imagePointSize: pointSize,
                                             center: CGPoint(x: visible.midX, y: visible.midY), visible: visible)
        let window = PinWindow(image: image, url: imageURL, frame: frame)
        window.onClose = { [weak self, weak window] in
            self?.pins.removeAll { $0 === window }
        }
        pins.append(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

/// A borderless, always-on-top window that shows one image.
final class PinWindow: NSPanel {
    let imageURL: URL
    let image: NSImage
    var onClose: (() -> Void)?
    private let pinView: PinView

    init(image: NSImage, url: URL, frame: NSRect) {
        self.image = image
        self.imageURL = url
        self.pinView = PinView(frame: NSRect(origin: .zero, size: frame.size))
        super.init(contentRect: frame, styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let aspect = frame.size
        contentAspectRatio = aspect
        minSize = NSSize(width: PinGeometry.minSide, height: PinGeometry.minSide)
        pinView.image = image
        pinView.owner = self
        contentView = pinView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { close() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { close(); return }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" { copyImage(); return }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "w" { close(); return }
        super.keyDown(with: event)
    }

    override func close() {
        super.close()
        onClose?()
        onClose = nil
    }

    func zoom(by factor: CGFloat, anchorInScreen anchor: CGPoint) {
        let maxSide = max(screen?.frame.width ?? 4000, screen?.frame.height ?? 4000) * 2
        let newFrame = PinGeometry.scaled(frame, by: factor, around: anchor, maxLongSide: maxSide)
        setFrame(newFrame, display: true)
    }

    func copyImage() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        pb.setString(imageURL.absoluteString, forType: .fileURL)
        Toast.show("Copied")
    }

    // MARK: Menu actions

    @objc func setOpacity(_ sender: NSMenuItem) {
        alphaValue = CGFloat(sender.tag) / 100
    }
    @objc func menuCopy() { copyImage() }
    @objc func menuAnnotate() { ActionRouter.shared.annotate(imageURL); close() }
    @objc func menuReveal() { NSWorkspace.shared.activateFileViewerSelecting([imageURL]) }
    @objc func menuActualSize() {
        let size = image.size
        setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                        width: size.width, height: size.height), display: true)
    }
    @objc func menuClose() { close() }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ sel: Selector, _ key: String = "") {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }
        add("Copy", #selector(menuCopy), "c")
        add("Annotate", #selector(menuAnnotate))
        add("Show in Finder", #selector(menuReveal))
        add("Actual Size", #selector(menuActualSize))
        menu.addItem(.separator())
        let opacity = NSMenuItem(title: "Opacity", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for step in PinGeometry.opacitySteps {
            let pct = Int((step * 100).rounded())
            let item = NSMenuItem(title: "\(pct) %", action: #selector(setOpacity(_:)), keyEquivalent: "")
            item.tag = pct
            item.target = self
            item.state = abs(alphaValue - step) < 0.01 ? .on : .off
            sub.addItem(item)
        }
        opacity.submenu = sub
        menu.addItem(opacity)
        menu.addItem(.separator())
        add("Close", #selector(menuClose), "w")
        return menu
    }
}

/// Draws the image with rounded corners and a thin border; a close button shows on hover.
final class PinView: NSView {
    weak var owner: PinWindow?
    var image: NSImage? { didSet { needsDisplay = true } }
    private let closeButton = NSButton()
    private var tracking: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        autoresizingMask = [.width, .height]

        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
        closeButton.isBordered = false
        closeButton.imageScaling = .scaleProportionallyUpOrDown
        closeButton.contentTintColor = .white
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.frame = NSRect(x: 6, y: frame.height - 26, width: 20, height: 20)
        closeButton.autoresizingMask = [.maxXMargin, .minYMargin]
        closeButton.isHidden = true
        closeButton.wantsLayer = true
        closeButton.layer?.shadowOpacity = 0.6
        closeButton.layer?.shadowRadius = 2
        addSubview(closeButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        image?.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true,
                    hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { closeButton.isHidden = false }
    override func mouseExited(with event: NSEvent) { closeButton.isHidden = true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, let owner {
            ActionRouter.shared.annotate(owner.imageURL)
            owner.close()
            return
        }
        super.mouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let owner else { return }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 4 : event.scrollingDeltaY * 2
        guard delta != 0 else { return }
        owner.zoom(by: PinGeometry.factor(forScrollDelta: delta), anchorInScreen: NSEvent.mouseLocation)
    }

    override func magnify(with event: NSEvent) {
        owner?.zoom(by: 1 + event.magnification, anchorInScreen: NSEvent.mouseLocation)
    }

    override func menu(for event: NSEvent) -> NSMenu? { owner?.makeMenu() }

    @objc private func closeClicked() { owner?.close() }
}
