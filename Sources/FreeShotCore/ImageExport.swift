import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageExportError: Error, CustomStringConvertible {
    case cannotCreateDestination(URL)
    case finalizeFailed(URL)

    public var description: String {
        switch self {
        case .cannotCreateDestination(let u): return "cannot write PNG to \(u.path)"
        case .finalizeFailed(let u): return "PNG write did not finish for \(u.path)"
        }
    }
}

public enum ImageExport {
    /// Writes a PNG with DPI metadata (72 × scale) so Preview shows the point size.
    public static func writePNG(_ image: CGImage, to url: URL, scale: CGFloat = 1) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ImageExportError.cannotCreateDestination(url)
        }
        let dpi = 72.0 * Double(max(scale, 1))
        let props: [CFString: Any] = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ImageExportError.finalizeFailed(url) }
    }

    public static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    public static func loadImage(at url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    /// Puts the image on the pasteboard as PNG + TIFF (via NSImage), sized in points.
    /// When `fileURL` is given it also goes on, so a paste into Finder makes a file.
    @discardableResult
    public static func copy(_ image: CGImage, scale: CGFloat = 1, fileURL: URL? = nil,
                            to pasteboard: NSPasteboard = .general) -> Bool {
        let size = NSSize(width: CGFloat(image.width) / max(scale, 1), height: CGFloat(image.height) / max(scale, 1))
        let ns = NSImage(cgImage: image, size: size)
        pasteboard.clearContents()
        // NSImage writes TIFF; PNG goes on the same item for apps that prefer it.
        let ok = pasteboard.writeObjects([ns])
        if let png = pngData(image) { pasteboard.setData(png, forType: .png) }
        if let fileURL { pasteboard.setString(fileURL.absoluteString, forType: .fileURL) }
        return ok
    }

    /// Puts a file URL on the pasteboard (used for recordings).
    @discardableResult
    public static func copyFile(_ url: URL, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.writeObjects([url as NSURL])
    }
}
