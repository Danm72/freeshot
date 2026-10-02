import AppKit
import FreeShotCore

/// A floating panel that never takes focus from the app you are working in.
final class QuickAccessPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// One Quick Access card: panel + view + its auto-close countdown.
final class QuickAccessCard {
    let item: QuickAccessItem
    var autoClose: QuickAccessAutoClose
    private(set) var isDragging = false
    private weak var controller: QuickAccessController?
    private let panel: QuickAccessPanel
    private let view: QuickAccessCardView

    init(item: QuickAccessItem, controller: QuickAccessController, autoClose: QuickAccessAutoClose) {
        self.item = item
        self.controller = controller
        self.autoClose = autoClose
        let size = QuickAccessLayout.cardSize(forImagePoints: item.pointSize)
        panel = QuickAccessPanel(frame: NSRect(origin: .zero, size: size))
        view = QuickAccessCardView(frame: NSRect(origin: .zero, size: size))
        view.card = self
        view.autoresizingMask = [.width, .height]
        panel.contentView = view
        view.reloadImage()
    }

    func place(_ frame: CGRect, animated: Bool) {
        if animated && panel.isVisible {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    /// Slides in from the screen edge on the overlay corner.
    func present() {
        let target = panel.frame
        let fromLeft = ModuleRegistry.shared.settings.overlayCorner == .bottomLeft
        var start = target
        start.origin.x += fromLeft ? -(target.width + 30) : (target.width + 30)
        panel.setFrame(start, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
    }

    func dismiss() {
        let p = panel
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 0
        }, completionHandler: { p.orderOut(nil) })
    }

    func flash(_ text: String, then: @escaping () -> Void) {
        view.showFlash(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: then)
    }

    // MARK: Events from the view

    func hoverChanged(_ inside: Bool) {
        if inside {
            autoClose.pause()
            if item.refreshIfChanged() { view.reloadImage() }
        } else {
            autoClose.resume(now: Date())
        }
    }

    func dragStarted() {
        isDragging = true
        panel.alphaValue = 0.35
    }

    func dragEnded(dropped: Bool) {
        isDragging = false
        if dropped {
            controller?.close(self)
        } else {
            panel.alphaValue = 1
            autoClose.resume(now: Date())
        }
    }

    func perform(_ action: QuickAccessCardView.Action) {
        guard let controller else { return }
        switch action {
        case .copy: controller.copy(self)
        case .save: controller.save(self)
        case .annotate: controller.annotate(self)
        case .pin: controller.pin(self)
        case .close: controller.close(self)
        }
    }
}
