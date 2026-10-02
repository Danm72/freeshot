import AppKit
import XCTest
@testable import FreeShotCore

final class ImageExportTests: XCTestCase {
    func makeImage(width: Int = 8, height: Int = 4) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    func testPNGRoundTripWithDPI() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("sub/Screenshot@2x.png")
        try ImageExport.writePNG(makeImage(), to: url, scale: 2)
        let back = try XCTUnwrap(ImageExport.loadImage(at: url))
        XCTAssertEqual(back.width, 8)
        XCTAssertEqual(back.height, 4)
        let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as! [CFString: Any]
        XCTAssertEqual(props[kCGImagePropertyDPIWidth] as? Double, 144)
        let head = try Data(contentsOf: url).prefix(8)
        XCTAssertEqual(Array(head), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    func testPNGData() {
        XCTAssertNotNil(ImageExport.pngData(makeImage()))
    }

    func testCopyToNamedPasteboard() throws {
        let pb = NSPasteboard(name: NSPasteboard.Name("freeshot.test.\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        let file = URL(fileURLWithPath: "/tmp/x.png")
        XCTAssertTrue(ImageExport.copy(makeImage(width: 20, height: 10), scale: 2, fileURL: file, to: pb))
        let types = pb.types ?? []
        XCTAssertTrue(types.contains(.png), "\(types)")
        XCTAssertTrue(types.contains(.tiff), "\(types)")
        let img = try XCTUnwrap(NSImage(pasteboard: pb))
        XCTAssertEqual(img.size.width, 10, accuracy: 0.01)
        XCTAssertEqual(pb.string(forType: .fileURL), file.absoluteString)
    }

    func testCopyFileURL() {
        let pb = NSPasteboard(name: NSPasteboard.Name("freeshot.test.\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        let url = URL(fileURLWithPath: "/tmp/rec.mp4")
        XCTAssertTrue(ImageExport.copyFile(url, to: pb))
        let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL]
        XCTAssertEqual(urls, [url])
    }
}
