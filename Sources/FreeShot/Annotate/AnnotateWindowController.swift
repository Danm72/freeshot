import AppKit
import FreeShotCore
import UniformTypeIdentifiers

/// The app has no main menu (LSUIElement), so the window routes ⌘ shortcuts itself.
final class AnnotateWindow: NSWindow {
    var keyHandler: ((NSEvent) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// Keeps a small document centred in the scroll view.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var r = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return r }
        let docFrame = doc.frame
        if r.width > docFrame.width { r.origin.x = (docFrame.width - r.width) / 2 }
        if r.height > docFrame.height { r.origin.y = (docFrame.height - r.height) / 2 }
        return r
    }
}

/// One editor window for one image file.
final class AnnotateWindowController: NSWindowController, NSWindowDelegate, AnnotateCanvasDelegate {
    private(set) var fileURL: URL
    var onClose: (() -> Void)?

    private let canvas: AnnotateCanvasView
    private let scrollView = NSScrollView()
    private var toolButtons: [AnnotationTool: NSButton] = [:]
    private var swatches: [ColorSwatchButton] = []
    private let widthPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private var undoButton: NSButton!
    private var redoButton: NSButton!
    private var clearCropButton: NSButton!
    private let scale: CGFloat

    init(fileURL: URL, image: CGImage, scale: CGFloat) {
        self.fileURL = fileURL
        self.scale = max(scale, 1)
        self.canvas = AnnotateCanvasView(image: image, scale: scale)
        let window = AnnotateWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 600),
                                    styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                    backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 720, height: 360)
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
        window.keyHandler = { [weak self] in self?.handleKeyEquivalent($0) ?? false }

        let settings = ModuleRegistry.shared.settings
        canvas.delegate = self
        canvas.tool = AnnotatePreferences.tool
        canvas.color = AnnotatePreferences.color
        canvas.strokeWidth = AnnotatePreferences.strokeWidth
        canvas.textSize = CGFloat(settings.annotateTextSize)
        canvas.pixelateIntensity = settings.pixelateIntensity

        buildContent()
        updateTitle()
        refreshToolbar()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Showing

    func present() {
        guard let window else { return }
        if !window.isVisible { sizeAndCenter() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
    }

    private func sizeAndCenter() {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let toolbarH: CGFloat = 52
        let maxContent = CGSize(width: visible.width * 0.9, height: visible.height * 0.9 - toolbarH)
        let img = canvas.frame.size
        let fit = min(1, maxContent.width / max(img.width, 1), maxContent.height / max(img.height, 1))
        let pad: CGFloat = 24
        let content = CGSize(width: max(window.minSize.width, img.width * fit + pad * 2),
                             height: max(window.minSize.height - toolbarH, img.height * fit + pad * 2) + toolbarH)
        window.setContentSize(content)
        let frame = window.frame
        window.setFrameOrigin(CGPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2))
        scrollView.magnification = fit
    }

    private func updateTitle() {
        window?.title = fileURL.lastPathComponent
        window?.representedURL = fileURL
        window?.isDocumentEdited = canvas.document.isDirty
    }

    // MARK: Layout

    private func buildContent() {
        guard let window else { return }
        let root = NSView()
        window.contentView = root

        let bar = NSVisualEffectView()
        bar.material = .titlebar
        bar.blendingMode = .withinWindow
        bar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(bar)

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(divider)

        let clip = CenteringClipView()
        clip.drawsBackground = false
        scrollView.contentView = clip
        scrollView.documentView = canvas
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.1
        scrollView.maxMagnification = 8
        scrollView.backgroundColor = .underPageBackgroundColor
        scrollView.drawsBackground = true
        scrollView.contentInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)

        for tool in AnnotationTool.allCases {
            let b = symbolButton(tool.symbolName, tip: "\(tool.title) (\(String(tool.shortcut).uppercased()))",
                                 action: #selector(toolClicked(_:)))
            b.setButtonType(.pushOnPushOff)
            b.tag = AnnotationTool.allCases.firstIndex(of: tool)!
            toolButtons[tool] = b
            stack.addArrangedSubview(b)
        }
        stack.addArrangedSubview(spacer(12))

        for (i, c) in RGBAColor.palette.enumerated() {
            let s = ColorSwatchButton(color: c)
            s.target = self
            s.action = #selector(colorClicked(_:))
            s.tag = i
            s.toolTip = "Colour"
            swatches.append(s)
            stack.addArrangedSubview(s)
        }
        stack.addArrangedSubview(spacer(8))

        for w in AnnotatePreferences.strokeWidths { widthPopup.addItem(withTitle: "\(Int(w)) pt") }
        widthPopup.target = self
        widthPopup.action = #selector(widthChanged(_:))
        widthPopup.controlSize = .small
        widthPopup.toolTip = "Stroke width"
        stack.addArrangedSubview(widthPopup)

        let flexible = NSView()
        flexible.setContentHuggingPriority(.init(1), for: .horizontal)
        stack.addArrangedSubview(flexible)

        clearCropButton = symbolButton("arrow.uturn.backward.square", tip: "Remove crop", action: #selector(clearCrop))
        undoButton = symbolButton("arrow.uturn.backward", tip: "Undo (⌘Z)", action: #selector(undoAction))
        redoButton = symbolButton("arrow.uturn.forward", tip: "Redo (⇧⌘Z)", action: #selector(redoAction))
        stack.addArrangedSubview(clearCropButton)
        stack.addArrangedSubview(undoButton)
        stack.addArrangedSubview(redoButton)
        stack.addArrangedSubview(spacer(8))
        stack.addArrangedSubview(symbolButton("doc.on.doc", tip: "Copy (⌘C)", action: #selector(copyAction)))
        stack.addArrangedSubview(symbolButton("square.and.arrow.down", tip: "Save (⌘S). Save As: ⇧⌘S", action: #selector(saveAction)))
        stack.addArrangedSubview(symbolButton("pin", tip: "Pin to screen", action: #selector(pinAction)))
        let drag = DragOutButton { [weak self] in self?.exportURL() }
        drag.toolTip = "Drag the image into another app"
        stack.addArrangedSubview(drag)

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: root.topAnchor),
            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 44),
            divider.topAnchor.constraint(equalTo: bar.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
    }

    private func symbolButton(_ symbol: String, tip: String, action: Selector) -> NSButton {
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
            ?? NSImage(systemSymbolName: "questionmark", accessibilityDescription: tip)!
        let b = NSButton(image: img, target: self, action: action)
        b.bezelStyle = .toolbar
        b.toolTip = tip
        b.setAccessibilityLabel(tip)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 30).isActive = true
        b.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return b
    }

    private func spacer(_ w: CGFloat) -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: w).isActive = true
        return v
    }

    private func refreshToolbar() {
        for (tool, b) in toolButtons { b.state = tool == canvas.tool ? .on : .off }
        for (i, s) in swatches.enumerated() { s.isChosen = RGBAColor.palette[i] == canvas.color }
        if let i = AnnotatePreferences.strokeWidths.firstIndex(of: canvas.strokeWidth) { widthPopup.selectItem(at: i) }
        undoButton.isEnabled = canvas.document.canUndo
        redoButton.isEnabled = canvas.document.canRedo
        clearCropButton.isEnabled = canvas.document.crop != nil
        updateTitle()
    }

    // MARK: Toolbar actions

    @objc private func toolClicked(_ sender: NSButton) { selectTool(AnnotationTool.allCases[sender.tag]) }

    private func selectTool(_ tool: AnnotationTool) {
        canvas.tool = tool
        AnnotatePreferences.tool = tool
        refreshToolbar()
        window?.makeFirstResponder(canvas)
    }

    @objc private func colorClicked(_ sender: NSButton) {
        let c = RGBAColor.palette[sender.tag]
        canvas.applyColor(c)
        AnnotatePreferences.color = c
        refreshToolbar()
    }

    @objc private func widthChanged(_ sender: NSPopUpButton) {
        let w = AnnotatePreferences.strokeWidths[max(0, sender.indexOfSelectedItem)]
        canvas.applyStrokeWidth(w)
        AnnotatePreferences.strokeWidth = w
        refreshToolbar()
        window?.makeFirstResponder(canvas)
    }

    @objc private func undoAction() { canvas.undo() }
    @objc private func redoAction() { canvas.redo() }
    @objc private func clearCrop() { canvas.clearCrop() }

    @objc private func copyAction() {
        guard let flat = canvas.flattened() else { return }
        ImageExport.copy(flat, scale: scale, fileURL: canvas.document.isDirty ? nil : fileURL)
    }

    @objc private func saveAction() { _ = save() }

    @objc private func pinAction() {
        guard let url = exportURL() else { return }
        ModuleRegistry.shared.pin.pin(imageURL: url)
    }

    // MARK: Files

    /// Overwrites the original file. Returns false on failure.
    @discardableResult
    private func save() -> Bool {
        guard let flat = canvas.flattened() else { return false }
        do {
            try ImageExport.writePNG(flat, to: fileURL, scale: scale)
            canvas.document.markSaved()
            refreshToolbar()
            NotificationCenter.default.post(name: .freeShotImageFileUpdated, object: fileURL)
            return true
        } catch {
            showError("FreeShot could not save the image", error)
            return false
        }
    }

    private func saveAs() {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.directoryURL = ModuleRegistry.shared.settings.saveFolder
        panel.nameFieldStringValue = fileURL.lastPathComponent
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url, let flat = self.canvas.flattened() else { return }
            do {
                try ImageExport.writePNG(flat, to: url, scale: self.scale)
                self.fileURL = url.standardizedFileURL
                self.canvas.document.markSaved()
                self.refreshToolbar()
                ModuleRegistry.shared.history.add(HistoryEntry(url: url))
                NotificationCenter.default.post(name: .freeShotHistoryChanged, object: nil)
                NotificationCenter.default.post(name: .freeShotImageFileUpdated, object: url)
            } catch {
                self.showError("FreeShot could not save the image", error)
            }
        }
    }

    /// A file that holds what the canvas shows: the original when nothing changed since the
    /// last save, else a flattened copy in the temp folder.
    private func exportURL() -> URL? {
        if !canvas.document.isDirty, !canvas.isEditingText { return fileURL }
        guard let flat = canvas.flattened() else { return nil }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FreeShot/Annotate/\(UUID().uuidString)", isDirectory: true)
        let url = dir.appendingPathComponent(fileURL.lastPathComponent)
        do {
            try ImageExport.writePNG(flat, to: url, scale: scale)
            return url
        } catch {
            showError("FreeShot could not export the image", error)
            return nil
        }
    }

    private func showError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "\(error)"
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    // MARK: Keys

    private func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard mods.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        let shift = mods.contains(.shift)
        // While text is being typed, the field editor owns copy, paste, select all and undo.
        if canvas.isEditingText, ["c", "v", "x", "a", "z"].contains(key) {
            return NSApp.sendAction(Self.editorSelector(key, shift: shift), to: nil, from: self)
        }
        switch (key, shift) {
        case ("z", false): canvas.undo()
        case ("z", true): canvas.redo()
        case ("c", false): copyAction()
        case ("s", false): save()
        case ("s", true): saveAs()
        case ("w", false): window?.performClose(nil)
        case ("=", _), ("+", _): zoom(by: 1.25)
        case ("-", false): zoom(by: 0.8)
        case ("0", false): scrollView.animator().magnification = 1
        case ("a", false), ("v", false), ("x", false): return false
        default: return false
        }
        return true
    }

    private static func editorSelector(_ key: String, shift: Bool) -> Selector {
        switch key {
        case "c": return #selector(NSText.copy(_:))
        case "v": return #selector(NSText.paste(_:))
        case "x": return #selector(NSText.cut(_:))
        case "a": return #selector(NSText.selectAll(_:))
        default: return shift ? Selector(("redo:")) : Selector(("undo:"))
        }
    }

    private func zoom(by factor: CGFloat) {
        let m = min(max(scrollView.magnification * factor, scrollView.minMagnification), scrollView.maxMagnification)
        scrollView.animator().magnification = m
    }

    // MARK: Canvas delegate

    func canvasDidChange(_ canvas: AnnotateCanvasView) { refreshToolbar() }
    func canvasSelectionDidChange(_ canvas: AnnotateCanvasView) {}
    func canvas(_ canvas: AnnotateCanvasView, requestsTool tool: AnnotationTool) { selectTool(tool) }

    // MARK: Window delegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard canvas.document.isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to \(fileURL.lastPathComponent)?"
        alert.informativeText = "Your annotations are lost if you do not save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return save()
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

/// A round colour swatch for the palette.
final class ColorSwatchButton: NSButton {
    let swatch: RGBAColor
    var isChosen = false { didSet { needsDisplay = true } }

    init(color: RGBAColor) {
        self.swatch = color
        super.init(frame: CGRect(x: 0, y: 0, width: 22, height: 22))
        isBordered = false
        title = ""
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 22).isActive = true
        heightAnchor.constraint(equalToConstant: 22).isActive = true
        setAccessibilityLabel("Colour \(color.hex)")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 4, dy: 4)
        let dot = NSBezierPath(ovalIn: r)
        NSColor(cgColor: swatch.cgColor)?.setFill()
        dot.fill()
        NSColor.separatorColor.setStroke()
        dot.lineWidth = 1
        dot.stroke()
        if isChosen {
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
            ring.lineWidth = 2
            NSColor.controlAccentColor.setStroke()
            ring.stroke()
        }
    }
}

/// A toolbar handle you drag to drop the current image into another app.
final class DragOutButton: NSView, NSDraggingSource {
    private let provider: () -> URL?
    private let icon = NSImageView()

    init(provider: @escaping () -> URL?) {
        self.provider = provider
        super.init(frame: CGRect(x: 0, y: 0, width: 30, height: 28))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 30).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
        icon.image = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: "Drag out")
        icon.contentTintColor = .secondaryLabelColor
        icon.frame = bounds.insetBy(dx: 5, dy: 4)
        icon.autoresizingMask = [.width, .height]
        addSubview(icon)
        setAccessibilityLabel("Drag the image into another app")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    override func mouseDown(with event: NSEvent) {
        guard let url = provider() else { return }
        // File URL first, so Finder and mail apps get a file; PNG data for apps that want pixels.
        let pbItem = NSPasteboardItem()
        pbItem.setString(url.absoluteString, forType: .fileURL)
        if let data = try? Data(contentsOf: url) { pbItem.setData(data, forType: .png) }
        let item = NSDraggingItem(pasteboardWriter: pbItem)
        let preview = NSImage(contentsOf: url) ?? NSImage()
        let maxSide: CGFloat = 160
        let s = preview.size
        let k = s.width > 0 && s.height > 0 ? min(1, maxSide / max(s.width, s.height)) : 1
        let size = CGSize(width: max(s.width * k, 32), height: max(s.height * k, 32))
        let p = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(CGRect(x: p.x - size.width / 2, y: p.y - size.height / 2,
                                     width: size.width, height: size.height), contents: preview)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy] : [.copy, .generic]
    }
}
