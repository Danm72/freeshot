import AppKit
import FreeShotCore

/// Tells the window controller about state the toolbar shows.
protocol AnnotateCanvasDelegate: AnyObject {
    func canvasDidChange(_ canvas: AnnotateCanvasView)
    func canvasSelectionDidChange(_ canvas: AnnotateCanvasView)
    func canvas(_ canvas: AnnotateCanvasView, requestsTool tool: AnnotationTool)
}

/// The drawing surface. Its frame is the image size in points; annotations live in image pixels.
final class AnnotateCanvasView: NSView, NSTextFieldDelegate {
    let image: CGImage
    let scale: CGFloat
    let document: AnnotationDocument
    weak var delegate: AnnotateCanvasDelegate?

    var tool: AnnotationTool = .arrow {
        didSet { if tool != oldValue { endTextEditing(commit: true); window?.invalidateCursorRects(for: self) } }
    }
    var color: RGBAColor = .red
    /// Stroke width in points.
    var strokeWidth: CGFloat = 4
    /// Text size in points.
    var textSize: CGFloat = 30
    /// Pixelate intensity in points (CleanShot's number).
    var pixelateIntensity: Double = 10

    private(set) var selectedID: UUID? {
        didSet { if selectedID != oldValue { delegate?.canvasSelectionDidChange(self); needsDisplay = true } }
    }

    private enum DragMode {
        case none
        case drawing
        case moving(last: CGPoint)
        case cropping(start: CGPoint)
    }

    private var drag: DragMode = .none
    private var draft: Annotation?
    private var cropDraft: CGRect?
    private let effects = AnnotationEffectCache()

    private var textField: NSTextField?
    private var editingID: UUID?
    private var editingOrigin: CGPoint = .zero

    init(image: CGImage, scale: CGFloat) {
        self.image = image
        self.scale = max(scale, 1)
        self.document = AnnotationDocument(imageSize: CGSize(width: image.width, height: image.height))
        super.init(frame: CGRect(x: 0, y: 0, width: CGFloat(image.width) / max(scale, 1),
                                 height: CGFloat(image.height) / max(scale, 1)))
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Coordinates

    private func imagePoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x * scale, y: p.y * scale)
    }

    /// Hit tolerance: 6 screen points, whatever the zoom.
    private var tolerance: CGFloat {
        let mag = enclosingScrollView?.magnification ?? 1
        return 6 * scale / max(mag, 0.05)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.scaleBy(x: 1 / scale, y: 1 / scale)
        ctx.interpolationQuality = .high
        let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        AnnotationRenderer.drawImage(image, in: full, ctx: ctx)
        for a in document.annotations where a.id != editingID {
            AnnotationRenderer.draw(a, in: ctx, source: image, cache: effects)
        }
        if let draft { AnnotationRenderer.draw(draft, in: ctx, source: image, cache: nil) }

        if let id = selectedID, let a = document.annotation(id: id), id != editingID {
            drawSelection(AnnotationHitTest.bounds(a), ctx: ctx)
        }
        drawCrop(ctx: ctx, full: full)
        ctx.restoreGState()
    }

    private func drawSelection(_ r: CGRect, ctx: CGContext) {
        let mag = enclosingScrollView?.magnification ?? 1
        let px = scale / max(mag, 0.05)
        let box = r.insetBy(dx: -4 * px, dy: -4 * px)
        ctx.saveGState()
        ctx.setLineWidth(1.5 * px)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.stroke(box)
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineDash(phase: 0, lengths: [4 * px, 3 * px])
        ctx.stroke(box)
        ctx.restoreGState()
    }

    private func drawCrop(ctx: CGContext, full: CGRect) {
        guard let crop = cropDraft ?? document.crop else { return }
        let mag = enclosingScrollView?.magnification ?? 1
        let px = scale / max(mag, 0.05)
        ctx.saveGState()
        ctx.setFillColor(CGColor(gray: 0, alpha: cropDraft == nil ? 0.65 : 0.45))
        ctx.addRect(full)
        ctx.addRect(crop)
        ctx.fillPath(using: .evenOdd)
        ctx.setStrokeColor(.white)
        ctx.setLineWidth(1.5 * px)
        ctx.stroke(crop)
        if cropDraft != nil {
            let label = SelectionMath.sizeLabel(for: CGRect(x: 0, y: 0, width: crop.width / scale, height: crop.height / scale),
                                                scale: scale) as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 12 * px, weight: .medium),
                                                         .foregroundColor: NSColor.white]
            let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ns
            label.draw(at: CGPoint(x: crop.minX + 6 * px, y: crop.minY + 6 * px), withAttributes: attrs)
            NSGraphicsContext.restoreGraphicsState()
        }
        ctx.restoreGState()
    }

    // MARK: Cursor

    override func resetCursorRects() {
        let cursor: NSCursor
        switch tool {
        case .select: cursor = .arrow
        case .text: cursor = .iBeam
        default: cursor = .crosshair
        }
        addCursorRect(visibleRect, cursor: cursor)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = imagePoint(event)

        if textField != nil { endTextEditing(commit: true) }

        // A click on the selected annotation moves it, whatever the tool.
        if let id = selectedID, let a = document.annotation(id: id),
           AnnotationHitTest.hits(a, point: p, tolerance: tolerance), tool != .crop {
            if event.clickCount == 2, a.kind == .text { beginTextEditing(existing: a); return }
            document.beginChange()
            drag = .moving(last: p)
            return
        }

        switch tool {
        case .select:
            if let hit = document.hitTest(p, tolerance: tolerance) {
                selectedID = hit
                if event.clickCount == 2, let a = document.annotation(id: hit), a.kind == .text {
                    beginTextEditing(existing: a)
                    return
                }
                document.beginChange()
                drag = .moving(last: p)
            } else {
                selectedID = nil
            }

        case .text:
            if let hit = document.hitTest(p, tolerance: tolerance), let a = document.annotation(id: hit), a.kind == .text {
                selectedID = hit
                beginTextEditing(existing: a)
            } else {
                selectedID = nil
                beginTextEditing(at: p)
            }

        case .counter:
            let a = Annotation(kind: .counter, points: [p], color: color, lineWidth: strokeWidth * scale,
                               number: document.nextCounterNumber())
            document.add(a)
            selectedID = a.id
            changed()

        case .crop:
            selectedID = nil
            drag = .cropping(start: p)
            cropDraft = CGRect(origin: p, size: .zero)
            needsDisplay = true

        default:
            guard let kind = tool.kind else { return }
            selectedID = nil
            var a = Annotation(kind: kind, points: [p, p], color: color, lineWidth: strokeWidth * scale,
                               fontSize: textSize * scale)
            if kind == .pixelate {
                a.intensity = CGFloat(AnnotateGeometry.pixelateBlockSize(intensity: pixelateIntensity, scale: scale))
            } else if kind == .blur {
                a.intensity = CGFloat(max(4, pixelateIntensity)) * scale
            }
            if kind.isFreehand { a.points = [p] }
            draft = a
            drag = .drawing
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = clampToImage(imagePoint(event))
        let shift = event.modifierFlags.contains(.shift)
        switch drag {
        case .none:
            return
        case .moving(let last):
            guard let id = selectedID else { return }
            document.update(id: id, registerUndo: false) { $0.translate(dx: p.x - last.x, dy: p.y - last.y) }
            drag = .moving(last: p)
        case .cropping(let start):
            let end = shift ? AnnotateGeometry.squareEnd(start: start, end: p) : p
            cropDraft = AnnotateGeometry.rect(from: start, to: end)
        case .drawing:
            guard var a = draft else { return }
            if a.kind.isFreehand {
                if shift, let first = a.points.first {
                    a.points = [first, AnnotateGeometry.snapAngle(start: first, end: p)]
                } else if let last = a.points.last, AnnotateGeometry.distance(last, p) >= 1 {
                    a.points.append(p)
                }
            } else {
                var end = p
                if shift {
                    end = a.kind.isSegment ? AnnotateGeometry.snapAngle(start: a.start, end: p)
                                           : AnnotateGeometry.squareEnd(start: a.start, end: p)
                }
                a.points = [a.start, end]
            }
            draft = a
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { drag = .none; needsDisplay = true }
        switch drag {
        case .none, .moving:
            if case .moving = drag { changed() }
        case .cropping:
            if let r = cropDraft, r.width >= 4, r.height >= 4 { document.setCrop(r); changed() }
            cropDraft = nil
        case .drawing:
            if let a = draft, !a.isDegenerate {
                document.add(a)
                selectedID = a.id
                changed()
            }
            draft = nil
        }
    }

    private func clampToImage(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), CGFloat(image.width)), y: min(max(p.y, 0), CGFloat(image.height)))
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        switch event.keyCode {
        case 51, 117: // delete, forward delete
            deleteSelection(); return
        case 53: // escape
            cancelCurrent(); return
        case 123, 124, 125, 126:
            nudge(event); return
        default: break
        }
        if mods.isEmpty, let c = event.charactersIgnoringModifiers?.first, let t = AnnotationTool.forShortcut(c) {
            delegate?.canvas(self, requestsTool: t)
            return
        }
        super.keyDown(with: event)
    }

    /// Esc: drops a drag or a selection. Returns false when there was nothing to cancel.
    @discardableResult
    func cancelCurrent() -> Bool {
        if textField != nil { endTextEditing(commit: false); return true }
        switch drag {
        case .moving:
            document.undo()
            drag = .none; changed()
            return true
        case .drawing, .cropping:
            draft = nil; cropDraft = nil; drag = .none; needsDisplay = true
            return true
        case .none:
            break
        }
        if selectedID != nil { selectedID = nil; return true }
        return false
    }

    func deleteSelection() {
        guard let id = selectedID else { return }
        document.remove(id: id)
        selectedID = nil
        changed()
    }

    private func nudge(_ event: NSEvent) {
        guard let id = selectedID else { return }
        let step = (event.modifierFlags.contains(.shift) ? 10 : 1) * scale
        var dx: CGFloat = 0, dy: CGFloat = 0
        switch event.keyCode {
        case 123: dx = -step
        case 124: dx = step
        case 125: dy = step
        default: dy = -step
        }
        document.update(id: id) { $0.translate(dx: dx, dy: dy) }
        changed()
    }

    // MARK: Edits from the toolbar

    func undo() {
        endTextEditing(commit: true)
        document.undo()
        if let id = selectedID, document.annotation(id: id) == nil { selectedID = nil }
        changed()
    }

    func redo() {
        endTextEditing(commit: true)
        document.redo()
        if let id = selectedID, document.annotation(id: id) == nil { selectedID = nil }
        changed()
    }

    /// Applies a palette colour to the selection too.
    func applyColor(_ c: RGBAColor) {
        color = c
        if let id = selectedID { document.update(id: id) { $0.color = c }; changed() }
        if let tf = textField { tf.textColor = NSColor(cgColor: c.cgColor) }
    }

    func applyStrokeWidth(_ w: CGFloat) {
        strokeWidth = w
        guard let id = selectedID, let a = document.annotation(id: id) else { return }
        if a.kind == .text {
            return
        }
        document.update(id: id) { $0.lineWidth = w * self.scale }
        changed()
    }

    func clearCrop() {
        document.setCrop(nil)
        changed()
    }

    /// The image as it will be saved.
    func flattened() -> CGImage? {
        endTextEditing(commit: true)
        if document.isEmpty { return image }
        return AnnotationRenderer.flatten(image: image, annotations: document.annotations, crop: document.crop)
    }

    private func changed() {
        needsDisplay = true
        delegate?.canvasDidChange(self)
    }

    // MARK: Text editing

    private func beginTextEditing(at p: CGPoint) {
        editingID = nil
        editingOrigin = p
        showTextField(text: "", color: color, fontSize: textSize * scale, origin: p)
    }

    private func beginTextEditing(existing a: Annotation) {
        editingID = a.id
        editingOrigin = a.start
        showTextField(text: a.text, color: a.color, fontSize: a.fontSize, origin: a.start)
        needsDisplay = true
    }

    private func showTextField(text: String, color: RGBAColor, fontSize: CGFloat, origin: CGPoint) {
        let tf = NSTextField(string: text)
        tf.isBordered = false
        tf.drawsBackground = false
        tf.isBezeled = false
        tf.focusRingType = .none
        tf.usesSingleLineMode = false
        tf.cell?.wraps = false
        tf.cell?.isScrollable = false
        tf.font = NSFont.systemFont(ofSize: fontSize / scale, weight: .semibold)
        tf.textColor = NSColor(cgColor: color.cgColor)
        tf.delegate = self
        tf.placeholderString = "Text"
        addSubview(tf)
        textField = tf
        layoutTextField()
        tf.setFrameOrigin(CGPoint(x: origin.x / scale - 2, y: origin.y / scale))
        window?.makeFirstResponder(tf)
        tf.currentEditor()?.selectedRange = NSRange(location: (text as NSString).length, length: 0)
    }

    private func layoutTextField() {
        guard let tf = textField else { return }
        tf.sizeToFit()
        var size = tf.frame.size
        size.width = max(size.width + 8, 40)
        tf.setFrameSize(size)
    }

    func controlTextDidChange(_ obj: Notification) { layoutTextField() }

    func controlTextDidEndEditing(_ obj: Notification) { endTextEditing(commit: true) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) { endTextEditing(commit: false); return true }
        return false
    }

    private func endTextEditing(commit: Bool) {
        guard let tf = textField else { return }
        textField = nil
        let text = tf.stringValue
        tf.delegate = nil
        tf.removeFromSuperview()
        defer {
            editingID = nil
            needsDisplay = true
            DispatchQueue.main.async { [weak self] in
                guard let self, self.textField == nil, let w = self.window, w.firstResponder !== self else { return }
                w.makeFirstResponder(self)
            }
        }
        guard commit else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = editingID {
            if trimmed.isEmpty { document.remove(id: id); selectedID = nil }
            else { document.update(id: id) { $0.text = text } }
            changed()
        } else if !trimmed.isEmpty {
            let a = Annotation(kind: .text, points: [editingOrigin], color: color, lineWidth: strokeWidth * scale,
                               text: text, fontSize: textSize * scale)
            document.add(a)
            selectedID = a.id
            changed()
        }
    }

    var isEditingText: Bool { textField != nil }
}
