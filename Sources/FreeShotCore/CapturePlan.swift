import CoreGraphics
import Foundation

/// What the after-capture pipeline does with one capture. Pure, so it is unit-tested.
public struct CapturePlan: Equatable, Sendable {
    public enum Copy: Equatable, Sendable {
        case none
        /// Image data, plus the file URL when the file is kept.
        case image
        /// The file URL only (recordings).
        case fileURL
    }

    /// Where the file ends up. Nil means no file is needed.
    public var fileURL: URL?
    /// True when `fileURL` is a scratch file (save is off but the overlay needs a file).
    public var isTemporary: Bool
    /// For recordings: the recorder's file must move to `fileURL` first.
    public var moveFrom: URL?
    public var addToHistory: Bool
    public var copy: Copy
    public var showOverlay: Bool

    public struct Options: Equatable, Sendable {
        public var save: Bool
        public var copy: Bool
        public var overlay: Bool
        public var saveFolder: URL
        public var tempFolder: URL

        public init(save: Bool, copy: Bool, overlay: Bool, saveFolder: URL, tempFolder: URL) {
            self.save = save
            self.copy = copy
            self.overlay = overlay
            self.saveFolder = saveFolder
            self.tempFolder = tempFolder
        }
    }

    public static var defaultTempFolder: URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("FreeShot", isDirectory: true)
    }

    /// True when `url` sits directly in `folder` (symlinks and trailing slashes resolved).
    public static func isInside(_ url: URL, folder: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path
            == folder.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// The `exists` check for `make`: a path is taken when it is on disk or reserved by a
    /// capture whose file is still being written.
    public static func existsCheck(reserved: Set<URL>,
                                   onDisk: @escaping (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) })
        -> (URL) -> Bool {
        { url in onDisk(url) || reserved.contains(url.standardizedFileURL) }
    }

    public static func make(kind: CaptureResult.Kind, scale: CGFloat, date: Date, options o: Options,
                            names: FilenameGenerator = FilenameGenerator(),
                            exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> CapturePlan {
        switch kind {
        case .screenshot:
            let needsFile = o.save || o.overlay
            var url: URL?
            if needsFile {
                let folder = o.save ? o.saveFolder : o.tempFolder
                url = names.uniqueURL(in: folder, kind: .screenshot(scale: scale), date: date, exists: exists)
            }
            return CapturePlan(fileURL: url, isTemporary: !o.save && url != nil, moveFrom: nil,
                               addToHistory: o.save, copy: o.copy ? .image : .none, showOverlay: o.overlay)
        case .recording(let source):
            // The recorder already wrote the file. Keep it where it is unless save is on and
            // it is outside the save folder.
            var target = source
            var move: URL?
            if o.save && !isInside(source, folder: o.saveFolder) {
                target = names.uniqueURL(in: o.saveFolder, kind: .recording, date: date, exists: exists)
                move = source
            }
            return CapturePlan(fileURL: target, isTemporary: !o.save, moveFrom: move,
                               addToHistory: o.save, copy: o.copy ? .fileURL : .none, showOverlay: o.overlay)
        }
    }
}
