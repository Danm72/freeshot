import AppKit
import XCTest
@testable import FreeShotCore

final class AnnotateGeometryTests: XCTestCase {
    func testArrowHeadPointsAlongTheShaft() {
        let head = AnnotateGeometry.arrowHead(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0), lineWidth: 4)
        XCTAssertEqual(head.tip, CGPoint(x: 100, y: 0))
        // 4.5 × 4 = 18 px long, 18 px wide.
        XCTAssertEqual(head.base.x, 82, accuracy: 1e-9)
        XCTAssertEqual(head.base.y, 0, accuracy: 1e-9)
        XCTAssertEqual(head.left.x, 82, accuracy: 1e-9)
        XCTAssertEqual(head.right.x, 82, accuracy: 1e-9)
        XCTAssertEqual(abs(head.left.y - head.right.y), 18, accuracy: 1e-9)
        XCTAssertEqual(head.left.y, -head.right.y, accuracy: 1e-9)
    }

    func testArrowHeadIsSymmetricOnADiagonal() {
        let s = CGPoint(x: 10, y: 10), e = CGPoint(x: 110, y: 110)
        let head = AnnotateGeometry.arrowHead(start: s, end: e, lineWidth: 8)
        let dl = AnnotateGeometry.distance(head.tip, head.left)
        let dr = AnnotateGeometry.distance(head.tip, head.right)
        XCTAssertEqual(dl, dr, accuracy: 1e-9)
        XCTAssertEqual(AnnotateGeometry.distance(head.tip, head.base), 36, accuracy: 1e-9)
    }

    func testArrowHeadNeverLongerThanShortArrow() {
        XCTAssertEqual(AnnotateGeometry.arrowHeadLength(lineWidth: 10, arrowLength: 20), 12, accuracy: 1e-9)
        XCTAssertEqual(AnnotateGeometry.arrowHeadLength(lineWidth: 1, arrowLength: 500), 12, accuracy: 1e-9)
        let zero = AnnotateGeometry.arrowHead(start: .zero, end: .zero, lineWidth: 4)
        XCTAssertEqual(zero.left, .zero)
    }

    func testSnapAngle() {
        let s = CGPoint(x: 0, y: 0)
        XCTAssertEqual(AnnotateGeometry.snapAngle(start: s, end: CGPoint(x: 100, y: 10)).y, 0, accuracy: 1e-9)
        let diag = AnnotateGeometry.snapAngle(start: s, end: CGPoint(x: 100, y: 90))
        XCTAssertEqual(diag.x, diag.y, accuracy: 1e-9)
        XCTAssertEqual(AnnotateGeometry.snapAngle(start: s, end: CGPoint(x: 5, y: -100)).x, 0, accuracy: 1e-9)
    }

    func testSquareEndKeepsDirection() {
        XCTAssertEqual(AnnotateGeometry.squareEnd(start: .zero, end: CGPoint(x: -30, y: 10)), CGPoint(x: -30, y: 30))
        XCTAssertEqual(AnnotateGeometry.squareEnd(start: .zero, end: CGPoint(x: 5, y: -40)), CGPoint(x: 40, y: -40))
    }

    func testCropClamping() {
        let size = CGSize(width: 200, height: 100)
        XCTAssertEqual(AnnotateGeometry.clampCrop(CGRect(x: -10, y: 20, width: 50, height: 500), to: size),
                       CGRect(x: 0, y: 20, width: 40, height: 80))
        // A reversed drag is standardised.
        XCTAssertEqual(AnnotateGeometry.clampCrop(CGRect(x: 60, y: 60, width: -40, height: -40), to: size),
                       CGRect(x: 20, y: 20, width: 40, height: 40))
        // Fractions snap to whole pixels.
        XCTAssertEqual(AnnotateGeometry.clampCrop(CGRect(x: 10.4, y: 10.6, width: 20.2, height: 20.5), to: size),
                       CGRect(x: 10, y: 11, width: 20, height: 21))
        XCTAssertNil(AnnotateGeometry.clampCrop(CGRect(x: 300, y: 0, width: 10, height: 10), to: size))
        XCTAssertNil(AnnotateGeometry.clampCrop(CGRect(x: -5, y: -5, width: 500, height: 500), to: size), "whole image = no crop")
        XCTAssertNil(AnnotateGeometry.clampCrop(CGRect(x: 5, y: 5, width: 0.2, height: 10), to: size))
    }

    func testPixelateBlockSize() {
        XCTAssertEqual(AnnotateGeometry.pixelateBlockSize(intensity: 10, scale: 2), 20)
        XCTAssertEqual(AnnotateGeometry.pixelateBlockSize(intensity: 10, scale: 1), 10)
        XCTAssertEqual(AnnotateGeometry.pixelateBlockSize(intensity: 0, scale: 2), 2)
    }

    func testPixelBlocksTileTheRectExactly() {
        let r = CGRect(x: 5, y: 7, width: 45, height: 25)
        let blocks = AnnotateGeometry.pixelBlocks(in: r, block: 20)
        XCTAssertEqual(blocks.count, 3 * 2)
        XCTAssertEqual(blocks.first, CGRect(x: 5, y: 7, width: 20, height: 20))
        XCTAssertEqual(blocks.last, CGRect(x: 45, y: 27, width: 5, height: 5))
        XCTAssertEqual(blocks.reduce(0) { $0 + $1.width * $1.height }, r.width * r.height)
        XCTAssertTrue(AnnotateGeometry.pixelBlocks(in: .zero, block: 10).isEmpty)
    }

    func testDistances() {
        XCTAssertEqual(AnnotateGeometry.distance(from: CGPoint(x: 5, y: 3), toSegment: .zero, CGPoint(x: 10, y: 0)), 3)
        XCTAssertEqual(AnnotateGeometry.distance(from: CGPoint(x: 13, y: 4), toSegment: .zero, CGPoint(x: 10, y: 0)), 5)
        let r = CGRect(x: 0, y: 0, width: 100, height: 50)
        XCTAssertEqual(AnnotateGeometry.distance(from: CGPoint(x: 50, y: 25), toRectEdge: r), 25)
        XCTAssertEqual(AnnotateGeometry.distance(from: CGPoint(x: 100, y: 0), toEllipseIn: r), 0, accuracy: 30)
        XCTAssertEqual(AnnotateGeometry.distance(from: CGPoint(x: 100, y: 25), toEllipseIn: r), 0, accuracy: 1e-9)
    }

    func testImageScale() {
        XCTAssertEqual(AnnotateGeometry.imageScale(dpi: 144, fileName: "x.png"), 2)
        XCTAssertEqual(AnnotateGeometry.imageScale(dpi: 72, fileName: "Screenshot 2026-10-02 at 10.21.18@2x.png"), 2)
        XCTAssertEqual(AnnotateGeometry.imageScale(dpi: nil, fileName: "Screenshot@3x (2).png"), 3)
        XCTAssertEqual(AnnotateGeometry.imageScale(dpi: nil, fileName: "photo.png"), 1)
    }

    func testImageScaleFromFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("plain.png")
        try ImageExport.writePNG(AnnotateRendererTests.solid(8, 8, .white), to: url, scale: 2)
        XCTAssertEqual(AnnotateGeometry.imageScale(of: url), 2)
    }
}

final class AnnotateModelTests: XCTestCase {
    func testToolShortcutsAreUnique() {
        let keys = AnnotationTool.allCases.map(\.shortcut)
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertEqual(AnnotationTool.forShortcut("A"), .arrow)
        XCTAssertNil(AnnotationTool.select.kind)
        XCTAssertEqual(AnnotationTool.pixelate.kind, .pixelate)
    }

    func testColorHexRoundTripAndContrast() {
        XCTAssertEqual(RGBAColor(hex: "#FF3B30")?.hex, "#FF3B30")
        XCTAssertEqual(RGBAColor(hex: "00ff0080")?.a ?? 0, 128.0 / 255, accuracy: 1e-9)
        XCTAssertNil(RGBAColor(hex: "#12"))
        XCTAssertEqual(RGBAColor.yellow.contrastingText, .black)
        XCTAssertEqual(RGBAColor.red.contrastingText, .white)
    }

    func testCounterNumbering() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 100, height: 100))
        XCTAssertEqual(doc.nextCounterNumber(), 1)
        for _ in 0..<3 {
            doc.add(Annotation(kind: .counter, points: [.zero], number: doc.nextCounterNumber()))
        }
        XCTAssertEqual(doc.annotations.map(\.number), [1, 2, 3])
        doc.remove(id: doc.annotations[1].id)
        XCTAssertEqual(doc.nextCounterNumber(), 4, "the next number follows the highest one")
        doc.remove(id: doc.annotations.last!.id)
        XCTAssertEqual(doc.nextCounterNumber(), 2)
        doc.add(Annotation(kind: .arrow, points: [.zero, CGPoint(x: 9, y: 9)]))
        XCTAssertEqual(doc.nextCounterNumber(), 2, "other kinds do not count")
    }

    func testUndoRedoAndDirty() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 100, height: 100))
        XCTAssertFalse(doc.isDirty)
        let a = Annotation(kind: .rectangle, points: [CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 50)])
        doc.add(a)
        XCTAssertTrue(doc.isDirty)
        doc.markSaved()
        XCTAssertFalse(doc.isDirty)

        // One drag-move = one undo step.
        doc.beginChange()
        for _ in 0..<5 { doc.update(id: a.id, registerUndo: false) { $0.translate(dx: 2, dy: 0) } }
        XCTAssertEqual(doc.annotation(id: a.id)?.start, CGPoint(x: 20, y: 10))
        doc.undo()
        XCTAssertEqual(doc.annotation(id: a.id)?.start, CGPoint(x: 10, y: 10))
        XCTAssertFalse(doc.isDirty)
        doc.redo()
        XCTAssertEqual(doc.annotation(id: a.id)?.start, CGPoint(x: 20, y: 10))

        doc.setCrop(CGRect(x: 0, y: 0, width: 40, height: 40))
        XCTAssertEqual(doc.crop, CGRect(x: 0, y: 0, width: 40, height: 40))
        doc.undo()
        XCTAssertNil(doc.crop)
        doc.undo(); doc.undo()
        XCTAssertTrue(doc.annotations.isEmpty)
        XCTAssertFalse(doc.canUndo)
        XCTAssertTrue(doc.canRedo)
        doc.add(a)
        XCTAssertFalse(doc.canRedo, "a new change drops the redo stack")
    }

    func testUpdateWithNoChangeAddsNoUndoStep() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 10, height: 10))
        let a = Annotation(kind: .line, points: [.zero, CGPoint(x: 5, y: 5)])
        doc.add(a)
        doc.undo(); doc.redo()
        doc.update(id: a.id) { _ in }
        doc.undo()
        XCTAssertTrue(doc.annotations.isEmpty)
    }

    func testHitTestPicksTopmost() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 200, height: 200))
        let box = Annotation(kind: .filledRectangle, points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100)])
        let line = Annotation(kind: .line, points: [CGPoint(x: 0, y: 50), CGPoint(x: 200, y: 50)], lineWidth: 4)
        doc.add(box); doc.add(line)
        XCTAssertEqual(doc.hitTest(CGPoint(x: 50, y: 51), tolerance: 2), line.id)
        XCTAssertEqual(doc.hitTest(CGPoint(x: 50, y: 80), tolerance: 2), box.id)
        XCTAssertNil(doc.hitTest(CGPoint(x: 150, y: 150), tolerance: 2))
        let ring = Annotation(kind: .rectangle, points: [CGPoint(x: 120, y: 120), CGPoint(x: 180, y: 180)], lineWidth: 4)
        doc.add(ring)
        XCTAssertNil(doc.hitTest(CGPoint(x: 150, y: 150), tolerance: 2), "an outline is not hit in its middle")
        XCTAssertEqual(doc.hitTest(CGPoint(x: 121, y: 150), tolerance: 2), ring.id)
    }

    func testDegenerate() {
        XCTAssertTrue(Annotation(kind: .arrow, points: [.zero, CGPoint(x: 1, y: 1)]).isDegenerate)
        XCTAssertFalse(Annotation(kind: .arrow, points: [.zero, CGPoint(x: 10, y: 1)]).isDegenerate)
        XCTAssertTrue(Annotation(kind: .text, points: [.zero], text: "  ").isDegenerate)
        XCTAssertFalse(Annotation(kind: .counter, points: [.zero]).isDegenerate)
        XCTAssertTrue(Annotation(kind: .pixelate, points: [.zero, CGPoint(x: 50, y: 2)]).isDegenerate)
    }
}

final class AnnotateRendererTests: XCTestCase {
    static func solid(_ w: Int, _ h: Int, _ color: RGBAColor) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    /// RGBA at a top-left pixel coordinate.
    func pixel(_ img: CGImage, _ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let w = img.width, h = img.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let i = (y * w + x) * 4
        return (buf[i], buf[i + 1], buf[i + 2], buf[i + 3])
    }

    func testFilledRectangleLandsTopLeft() throws {
        let base = Self.solid(100, 80, .white)
        let box = Annotation(kind: .filledRectangle, points: [CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 20)],
                             color: RGBAColor(r: 0, g: 0, b: 1), lineWidth: 0)
        let out = try XCTUnwrap(AnnotationRenderer.flatten(image: base, annotations: [box]))
        XCTAssertEqual(out.width, 100)
        let inside = pixel(out, 10, 10)
        XCTAssertEqual(inside.2, 255); XCTAssertEqual(inside.0, 0)
        let below = pixel(out, 10, 60)
        XCTAssertEqual(below.0, 255, "the box is at the top, not the bottom")
    }

    func testArrowDrawsAlongItsPath() throws {
        let base = Self.solid(200, 100, .white)
        let arrow = Annotation(kind: .arrow, points: [CGPoint(x: 10, y: 50), CGPoint(x: 190, y: 50)],
                               color: RGBAColor(r: 1, g: 0, b: 0), lineWidth: 6)
        let out = try XCTUnwrap(AnnotationRenderer.flatten(image: base, annotations: [arrow]))
        let mid = pixel(out, 100, 50)
        XCTAssertEqual(mid.0, 255); XCTAssertLessThan(mid.1, 30)
        // The head is 27 px long and wide near the tip.
        let head = pixel(out, 170, 58)
        XCTAssertLessThan(head.1, 60)
        XCTAssertEqual(pixel(out, 100, 10).1, 255)
    }

    func testCropShrinksOutput() throws {
        let base = Self.solid(100, 80, .white)
        let box = Annotation(kind: .filledRectangle, points: [CGPoint(x: 50, y: 40), CGPoint(x: 100, y: 80)],
                             color: RGBAColor(r: 0, g: 1, b: 0), lineWidth: 0)
        let out = try XCTUnwrap(AnnotationRenderer.flatten(image: base, annotations: [box],
                                                           crop: CGRect(x: 40, y: 30, width: 30, height: 20)))
        XCTAssertEqual(out.width, 30)
        XCTAssertEqual(out.height, 20)
        XCTAssertEqual(pixel(out, 0, 0).0, 255, "top-left of the crop is outside the box")
        XCTAssertEqual(pixel(out, 25, 15).1, 255)
        XCTAssertEqual(pixel(out, 25, 15).0, 0)
    }

    func testPixelateAveragesEachBlock() throws {
        // Left half black, right half white: a 20 px block across the seam goes grey.
        let ctx = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(.white); ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        ctx.setFillColor(.black); ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        let src = ctx.makeImage()!
        let patch = try XCTUnwrap(AnnotationRenderer.pixelate(src, rect: CGRect(x: 10, y: 0, width: 20, height: 20), block: 20))
        XCTAssertEqual(patch.width, 20)
        let a = pixel(patch, 0, 0), b = pixel(patch, 19, 19)
        XCTAssertEqual(a.0, b.0)
        XCTAssertEqual(Int(a.0), 127, accuracy: 2)
    }

    func testPixelateAnnotationInFlatten() throws {
        let base = Self.solid(60, 60, RGBAColor(r: 0.2, g: 0.4, b: 0.6))
        let px = Annotation(kind: .pixelate, points: [CGPoint(x: 0, y: 0), CGPoint(x: 30, y: 30)], intensity: 10)
        let out = try XCTUnwrap(AnnotationRenderer.flatten(image: base, annotations: [px]))
        XCTAssertEqual(Int(pixel(out, 5, 5).2), 153, accuracy: 2, "a solid area stays the same colour")
    }

    func testBlurKeepsSize() throws {
        let src = Self.solid(50, 50, .red)
        let out = try XCTUnwrap(AnnotationRenderer.blur(src, rect: CGRect(x: 5, y: 5, width: 20, height: 10), radius: 6))
        XCTAssertEqual(out.width, 20)
        XCTAssertEqual(out.height, 10)
        XCTAssertEqual(Int(pixel(out, 0, 0).0), 255, accuracy: 3, "no dark fringe at the edge")
    }

    func testTextAndCounterRender() throws {
        let base = Self.solid(300, 120, .white)
        let text = Annotation(kind: .text, points: [CGPoint(x: 10, y: 10)], color: .black, text: "Hello", fontSize: 60)
        let counter = Annotation(kind: .counter, points: [CGPoint(x: 250, y: 60)], color: .blue, lineWidth: 8, number: 7)
        let bounds = AnnotationRenderer.textBounds(text)
        XCTAssertGreaterThan(bounds.width, 100)
        XCTAssertGreaterThan(bounds.height, 50)
        XCTAssertEqual(bounds.origin, CGPoint(x: 10, y: 10))
        let out = try XCTUnwrap(AnnotationRenderer.flatten(image: base, annotations: [text, counter]))
        // Some dark pixels inside the text box, none far below it.
        var dark = 0
        for y in stride(from: 10, to: Int(bounds.maxY), by: 2) {
            for x in stride(from: 10, to: Int(bounds.maxX), by: 2) where pixel(out, x, y).0 < 80 { dark += 1 }
        }
        XCTAssertGreaterThan(dark, 10)
        XCTAssertEqual(pixel(out, 20, 115).0, 255)
        // The counter edge is blue (the number sits in the middle).
        let edge = pixel(out, 250 - 25, 60)
        XCTAssertGreaterThan(edge.2, 200); XCTAssertLessThan(edge.0, 60)
    }

    func testHitTestBoundsForCounterAndText() {
        let c = Annotation(kind: .counter, points: [CGPoint(x: 50, y: 50)], lineWidth: 8)
        let r = AnnotateGeometry.counterRadius(lineWidth: 8)
        XCTAssertEqual(AnnotationHitTest.bounds(c), CGRect(x: 50 - r, y: 50 - r, width: 2 * r, height: 2 * r))
        XCTAssertTrue(AnnotationHitTest.hits(c, point: CGPoint(x: 50 + r - 1, y: 50), tolerance: 0))
        XCTAssertFalse(AnnotationHitTest.hits(c, point: CGPoint(x: 50 + r + 5, y: 50), tolerance: 0))
    }
}
