import AppKit
import FreeShotCore

/// One capture shown in the Quick Access Overlay.
final class QuickAccessItem {
    /// Changes when Save moves a scratch file into the save folder.
    var fileURL: URL
    var image: CGImage?
    let scale: CGFloat
    let isRecording: Bool
    var isTemporary: Bool
    /// Modification date of the file when `image` was loaded, so an Annotate save refreshes it.
    var imageDate: Date?

    init(fileURL: URL, image: CGImage?, scale: CGFloat, isRecording: Bool, isTemporary: Bool) {
        self.fileURL = fileURL
        self.image = image
        self.scale = scale
        self.isRecording = isRecording
        self.isTemporary = isTemporary
        self.imageDate = Self.modificationDate(fileURL)
    }

    /// The image size in points (pixels / scale).
    var pointSize: CGSize {
        guard let image else { return CGSize(width: 16, height: 10) }
        let s = max(scale, 1)
        return CGSize(width: CGFloat(image.width) / s, height: CGFloat(image.height) / s)
    }

    /// Reloads the thumbnail when the file changed on disk (for example after Annotate saved it).
    func refreshIfChanged() -> Bool {
        guard !isRecording, let date = Self.modificationDate(fileURL), date != imageDate,
              let fresh = ImageExport.loadImage(at: fileURL) else { return false }
        image = fresh
        imageDate = date
        return true
    }

    static func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}

/// Owns the stack of Quick Access cards: placement, auto-close and the card actions.
final class QuickAccessController {
    static let shared = QuickAccessController()

    private var cards: [QuickAccessCard] = []   // newest first
    private var screen: NSScreen?
    private var ticker: Timer?
    private var registry: ModuleRegistry { .shared }

    private init() {
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.relayout(animated: false) }
    }

    var visibleCount: Int { cards.count }

    func show(_ item: QuickAccessItem, displayID: CGDirectDisplayID?) {
        dispatchPrecondition(condition: .onQueue(.main))
        screen = displayID.flatMap(Self.screen(for:)) ?? DisplayCapture.screenUnderMouse() ?? NSScreen.main
        let card = QuickAccessCard(item: item, controller: self,
                                   autoClose: QuickAccessAutoClose(duration: registry.settings.overlayAutoCloseSeconds, now: Date()))
        cards.insert(card, at: 0)
        relayout(animated: true, newCard: card)
        card.present()
        startTicker()
    }

    func close(_ card: QuickAccessCard) {
        guard let i = cards.firstIndex(where: { $0 === card }) else { return }
        cards.remove(at: i)
        card.dismiss()
        relayout(animated: true)
        if cards.isEmpty { ticker?.invalidate(); ticker = nil }
    }

    func closeAll() {
        for card in cards { card.dismiss() }
        cards.removeAll()
        ticker?.invalidate(); ticker = nil
    }

    // MARK: Layout

    private func relayout(animated: Bool, newCard: QuickAccessCard? = nil) {
        guard let screen = screen ?? NSScreen.main else { return }
        let layout = QuickAccessLayout(corner: registry.settings.overlayCorner)
        let sizes = cards.map { QuickAccessLayout.cardSize(forImagePoints: $0.item.pointSize) }
        let frames = layout.frames(for: sizes, in: screen.visibleFrame)
        var overflow: [QuickAccessCard] = []
        for (card, frame) in zip(cards, frames) {
            guard let frame else { overflow.append(card); continue }
            card.place(frame, animated: animated && card !== newCard)
        }
        for card in overflow { close(card) }
    }

    // MARK: Auto-close

    private func startTicker() {
        guard ticker == nil else { return }
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func tick() {
        let now = Date()
        for card in cards where card.autoClose.isExpired(now: now) && !card.isDragging { close(card) }
    }

    // MARK: Actions (called by cards)

    func copy(_ card: QuickAccessCard) {
        let item = card.item
        if item.isRecording {
            ImageExport.copyFile(item.fileURL)
        } else {
            _ = item.refreshIfChanged()
            guard let image = item.image else { return }
            ImageExport.copy(image, scale: item.scale, fileURL: item.isTemporary ? nil : item.fileURL)
        }
        card.flash("Copied") { [weak self] in self?.close(card) }
    }

    /// Moves a scratch file into the save folder when needed, then reveals it in Finder.
    func save(_ card: QuickAccessCard) {
        let item = card.item
        if item.isTemporary {
            let settings = registry.settings
            let kind: FilenameGenerator.Kind = item.isRecording ? .recording : .screenshot(scale: item.scale)
            let target = FilenameGenerator().uniqueURL(in: settings.saveFolder, kind: kind, date: Date())
            do {
                try FileManager.default.createDirectory(at: settings.saveFolder, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: item.fileURL, to: target)
                item.fileURL = target
                item.isTemporary = false
                registry.history.add(HistoryEntry(url: target, kind: item.isRecording ? .recording : .screenshot))
                NotificationCenter.default.post(name: .freeShotHistoryChanged, object: nil)
            } catch {
                QuickAccessPipeline.log("save from Quick Access failed: \(error)")
                NSSound.beep()
                return
            }
        }
        NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
        close(card)
    }

    func annotate(_ card: QuickAccessCard) {
        let url = card.item.fileURL
        close(card)
        if card.item.isRecording { NSWorkspace.shared.open(url) } else { ActionRouter.shared.annotate(url) }
    }

    func pin(_ card: QuickAccessCard) {
        let url = card.item.fileURL
        close(card)
        ActionRouter.shared.pin(url)
    }

    // MARK: Helpers

    static func screen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { DisplayCapture.displayID(of: $0) == id }
    }
}
