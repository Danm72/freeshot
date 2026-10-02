import AppKit
import FreeShotCore

extension Notification.Name {
    /// Posted with the file URL as `object` after Annotate overwrites or creates an image file.
    /// Quick Access thumbnails can observe it to refresh.
    static let freeShotImageFileUpdated = Notification.Name("FreeShotImageFileUpdated")
}

/// The concrete AnnotateModule. Assign it in ModuleRegistry.installDefaults():
/// `annotate = AnnotateController()`.
final class AnnotateController: AnnotateModule {
    private var windows: [AnnotateWindowController] = []

    func open(imageURL: URL) {
        dispatchPrecondition(condition: .onQueue(.main))
        let url = imageURL.standardizedFileURL
        if let existing = windows.first(where: { $0.fileURL == url }) {
            existing.present()
            return
        }
        guard let image = ImageExport.loadImage(at: url) else {
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "FreeShot cannot open this image"
            alert.informativeText = url.path
            alert.runModal()
            return
        }
        let wc = AnnotateWindowController(fileURL: url, image: image, scale: AnnotateGeometry.imageScale(of: url))
        wc.onClose = { [weak self, weak wc] in self?.windows.removeAll { $0 === wc } }
        windows.append(wc)
        wc.present()
    }
}

/// The last tool, colour and width, kept across editor windows and launches.
enum AnnotatePreferences {
    private static let defaults = UserDefaults.standard
    private static let toolKey = "annotateLastTool"
    private static let colorKey = "annotateLastColor"
    private static let widthKey = "annotateStrokeWidth"

    static let strokeWidths: [CGFloat] = [2, 4, 6, 8, 12]

    static var tool: AnnotationTool {
        get { defaults.string(forKey: toolKey).flatMap(AnnotationTool.init(rawValue:)) ?? .arrow }
        set { defaults.set(newValue.rawValue, forKey: toolKey) }
    }

    static var color: RGBAColor {
        get { defaults.string(forKey: colorKey).flatMap(RGBAColor.init(hex:)) ?? .red }
        set { defaults.set(newValue.hex, forKey: colorKey) }
    }

    static var strokeWidth: CGFloat {
        get { defaults.object(forKey: widthKey) == nil ? 4 : CGFloat(defaults.double(forKey: widthKey)) }
        set { defaults.set(Double(newValue), forKey: widthKey) }
    }
}
