import AppKit
import FreeShotCore

/// A button that reacts to the first click in a panel that is never key.
final class QuickAccessButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The card content: thumbnail, hover controls, drag-out and double-click.
final class QuickAccessCardView: NSView, NSDraggingSource {
    enum Action { case copy, save, annotate, pin, close }

    weak var card: QuickAccessCard?

    private let imageLayer = CALayer()
    private let hoverView = NSView()
    private let flashLabel = NSTextField(labelWithString: "")
    private var tracking: NSTrackingArea?
    private var mouseDownPoint: NSPoint?
    private let cornerRadius: CGFloat = 10

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor

        imageLayer.contentsGravity = .resizeAspect
        imageLayer.magnificationFilter = .trilinear
        imageLayer.minificationFilter = .trilinear
        layer?.addSublayer(imageLayer)

        buildHoverControls()

        flashLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        flashLabel.textColor = .white
        flashLabel.alignment = .center
        flashLabel.wantsLayer = true
        flashLabel.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        flashLabel.isHidden = true
        addSubview(flashLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Buttons get their own clicks. Every other click lands on the card itself, so the
    /// first click in this never-key panel can start a drag or a double-click.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if hit == nil || hit is NSButton { return hit }
        return self
    }

    func reloadImage() {
        guard let item = card?.item else { return }
        imageLayer.contents = item.image
        imageLayer.contentsScale = window?.backingScaleFactor ?? 2
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        CATransaction.commit()
        hoverView.frame = bounds
        flashLabel.frame = NSRect(x: 0, y: bounds.midY - 14, width: bounds.width, height: 28)
    }

    // MARK: Hover controls

    private func buildHoverControls() {
        hoverView.wantsLayer = true
        hoverView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        hoverView.isHidden = true
        hoverView.autoresizingMask = [.width, .height]
        addSubview(hoverView)

        let copy = pill("Copy", action: .copy)
        let save = pill("Save", action: .save)
        let stack = NSStackView(views: [copy, save])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        hoverView.addSubview(stack)

        let close = icon("xmark", tip: "Close", action: .close)
        let pin = icon("pin.fill", tip: "Pin to screen", action: .pin)
        let annotate = icon("pencil.and.outline", tip: "Annotate", action: .annotate)
        for v in [close, pin, annotate] { hoverView.addSubview(v) }

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: hoverView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: hoverView.centerYAnchor),
            copy.widthAnchor.constraint(equalToConstant: 84),
            save.widthAnchor.constraint(equalToConstant: 84),
            close.leadingAnchor.constraint(equalTo: hoverView.leadingAnchor, constant: 6),
            close.topAnchor.constraint(equalTo: hoverView.topAnchor, constant: 6),
            pin.trailingAnchor.constraint(equalTo: hoverView.trailingAnchor, constant: -6),
            pin.topAnchor.constraint(equalTo: hoverView.topAnchor, constant: 6),
            annotate.trailingAnchor.constraint(equalTo: hoverView.trailingAnchor, constant: -6),
            annotate.bottomAnchor.constraint(equalTo: hoverView.bottomAnchor, constant: -6),
        ])
        pinButton = pin
        annotateButton = annotate
    }

    private var pinButton: NSButton?
    private var annotateButton: NSButton?

    /// Recordings cannot be pinned; their pencil button opens the video instead.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let isRecording = card?.item.isRecording ?? false
        pinButton?.isHidden = isRecording
        if isRecording {
            annotateButton?.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Open")
            annotateButton?.toolTip = "Open"
        }
        reloadImage()
    }

    private func pill(_ title: String, action: Action) -> NSButton {
        let b = QuickAccessButton(title: title, target: self, action: #selector(buttonPressed(_:)))
        b.tag = tag(for: action)
        b.isBordered = false
        b.wantsLayer = true
        b.layer?.cornerRadius = 13
        b.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
        b.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.black,
        ])
        b.translatesAutoresizingMaskIntoConstraints = false
        b.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return b
    }

    private func icon(_ symbol: String, tip: String, action: Action) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .bold)) ?? NSImage()
        let b = QuickAccessButton(image: image, target: self, action: #selector(buttonPressed(_:)))
        b.tag = tag(for: action)
        b.toolTip = tip
        b.isBordered = false
        b.contentTintColor = .black
        b.wantsLayer = true
        b.layer?.cornerRadius = 11
        b.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 22).isActive = true
        b.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return b
    }

    private static let actions: [Action] = [.copy, .save, .annotate, .pin, .close]
    private func tag(for action: Action) -> Int { Self.actions.firstIndex(of: action)! }

    @objc private func buttonPressed(_ sender: NSButton) {
        card?.perform(Self.actions[sender.tag])
    }

    func showFlash(_ text: String) {
        hoverView.isHidden = true
        flashLabel.stringValue = text
        flashLabel.isHidden = false
    }

    // MARK: Hover tracking (.activeAlways: the app is rarely active)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) {
        guard flashLabel.isHidden else { return }
        hoverView.isHidden = false
        card?.hoverChanged(true)
    }

    override func mouseExited(with event: NSEvent) {
        hoverView.isHidden = true
        card?.hoverChanged(false)
    }

    // MARK: Click, double-click, drag-out

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownPoint = nil }
        if event.clickCount == 2 { card?.perform(.annotate) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, let card else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard hypot(p.x - start.x, p.y - start.y) > 4 else { return }
        mouseDownPoint = nil

        let url = card.item.fileURL
        let pbItem = NSPasteboardItem()
        pbItem.setString(url.absoluteString, forType: .fileURL)
        if !card.item.isRecording, let data = try? Data(contentsOf: url) {
            pbItem.setData(data, forType: .png)
        }
        let dragItem = NSDraggingItem(pasteboardWriter: pbItem)
        let thumb = NSImage(size: bounds.size)
        if let image = card.item.image {
            thumb.addRepresentation(NSBitmapImageRep(cgImage: image))
        }
        dragItem.setDraggingFrame(bounds, contents: thumb)
        let session = beginDraggingSession(with: [dragItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        card.dragStarted()
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .generic] : .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        card?.dragEnded(dropped: operation != [])
    }
}
