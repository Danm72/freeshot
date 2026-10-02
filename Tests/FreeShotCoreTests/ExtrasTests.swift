import CoreGraphics
import XCTest
@testable import FreeShotCore

final class RecordingGeometryTests: XCTestCase {
    let primary = DisplayDescriptor(id: 1, cocoaFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), scale: 2)
    let right = DisplayDescriptor(id: 2, cocoaFrame: CGRect(x: 1512, y: 0, width: 1920, height: 1080), scale: 1)
    var space: CoordinateSpace { CoordinateSpace(displays: [primary, right]) }

    func testWholeDisplayWhenRectIsNil() throws {
        let g = try XCTUnwrap(RecordingGeometry.make(rect: nil, on: primary, space: space))
        XCTAssertEqual(g.sourceRect, CGRect(x: 0, y: 0, width: 1512, height: 982))
        XCTAssertEqual(g.pixelWidth, 3024)
        XCTAssertEqual(g.pixelHeight, 1964)
    }

    func testAreaIsFlippedToTopLeftLocalPoints() throws {
        // 100 pt from the left, 200 pt up from the bottom, 300 x 100 pt.
        let g = try XCTUnwrap(RecordingGeometry.make(rect: CGRect(x: 100, y: 200, width: 300, height: 100), on: primary, space: space))
        XCTAssertEqual(g.sourceRect, CGRect(x: 100, y: 982 - 300, width: 300, height: 100))
        XCTAssertEqual(g.pixelWidth, 600)
        XCTAssertEqual(g.pixelHeight, 200)
    }

    func testOddPixelSizeRoundsDownToEven() throws {
        let g = try XCTUnwrap(RecordingGeometry.make(rect: CGRect(x: 1600, y: 10, width: 301, height: 151), on: right, space: space))
        XCTAssertEqual(g.pixelWidth, 300)
        XCTAssertEqual(g.pixelHeight, 150)
        XCTAssertEqual(g.sourceRect.width, 300)
        XCTAssertEqual(g.sourceRect.height, 150)
        // Local to the right display: x = 1600 - 1512.
        XCTAssertEqual(g.sourceRect.minX, 88)
    }

    func testRectIsClippedToDisplay() throws {
        let g = try XCTUnwrap(RecordingGeometry.make(rect: CGRect(x: 1400, y: 0, width: 300, height: 100), on: primary, space: space))
        XCTAssertEqual(g.cocoaRect.maxX, 1512)
        XCTAssertEqual(g.pixelWidth, 224)
    }

    func testRectOffDisplayIsNil() {
        XCTAssertNil(RecordingGeometry.make(rect: CGRect(x: 2000, y: 0, width: 100, height: 100), on: primary, space: space))
    }

    func testEvenHasMinimumOfTwo() {
        XCTAssertEqual(RecordingGeometry.even(1), 2)
        XCTAssertEqual(RecordingGeometry.even(7.9), 6)
    }
}

final class OCRTextAssemblerTests: XCTestCase {
    func testRowsTopToBottomAndLeftToRight() {
        let lines = [
            OCRLine(text: "world", box: CGRect(x: 0.5, y: 0.80, width: 0.2, height: 0.05)),
            OCRLine(text: "second line", box: CGRect(x: 0.1, y: 0.60, width: 0.4, height: 0.05)),
            OCRLine(text: "hello", box: CGRect(x: 0.1, y: 0.81, width: 0.2, height: 0.05)),
        ]
        XCTAssertEqual(OCRTextAssembler.assemble(lines), "hello world\nsecond line")
    }

    func testEmptyInput() {
        XCTAssertEqual(OCRTextAssembler.assemble([]), "")
        XCTAssertEqual(OCRTextAssembler.assemble([OCRLine(text: "  ", box: .zero)]), "")
    }

    func testLinksAreFound() {
        let links = OCRTextAssembler.links(in: "see https://mawla.ie/x and dan@example.com")
        XCTAssertEqual(links.count, 2)
        XCTAssertEqual(links.first?.absoluteString, "https://mawla.ie/x")
    }

    func testToastMessage() {
        XCTAssertEqual(OCRTextAssembler.toastMessage(for: ""), "No text found")
        XCTAssertEqual(OCRTextAssembler.toastMessage(for: "one"), "Copied 1 line")
        XCTAssertEqual(OCRTextAssembler.toastMessage(for: "a\nhttps://x.com"), "Copied 2 lines · 1 link")
    }
}

final class PinGeometryTests: XCTestCase {
    func testInitialFrameFitsAndCentres() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let f = PinGeometry.initialFrame(imagePointSize: CGSize(width: 400, height: 200), center: CGPoint(x: 500, y: 400), visible: visible)
        XCTAssertEqual(f, CGRect(x: 300, y: 300, width: 400, height: 200))
    }

    func testInitialFrameShrinksLargeImage() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let f = PinGeometry.initialFrame(imagePointSize: CGSize(width: 2000, height: 1000), center: CGPoint(x: 500, y: 400), visible: visible)
        XCTAssertEqual(f.width, 800)
        XCTAssertEqual(f.height, 400)
        XCTAssertTrue(visible.contains(f))
    }

    func testScaledKeepsAnchorAndAspect() {
        let frame = CGRect(x: 100, y: 100, width: 200, height: 100)
        let anchor = CGPoint(x: 100, y: 100)
        let s = PinGeometry.scaled(frame, by: 2, around: anchor)
        XCTAssertEqual(s, CGRect(x: 100, y: 100, width: 400, height: 200))
        let c = PinGeometry.scaled(frame, by: 0.5, around: CGPoint(x: 200, y: 150))
        XCTAssertEqual(c, CGRect(x: 150, y: 125, width: 100, height: 50))
    }

    func testScaledClampsToMinimum() {
        let frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        let s = PinGeometry.scaled(frame, by: 0.01, around: .zero)
        XCTAssertEqual(s.height, PinGeometry.minSide, accuracy: 0.001)
        XCTAssertEqual(s.width, PinGeometry.minSide * 2, accuracy: 0.001)
    }

    func testScrollFactorDirection() {
        XCTAssertGreaterThan(PinGeometry.factor(forScrollDelta: 5), 1)
        XCTAssertLessThan(PinGeometry.factor(forScrollDelta: -5), 1)
        XCTAssertEqual(PinGeometry.factor(forScrollDelta: 1000), PinGeometry.factor(forScrollDelta: 20))
    }
}

final class HotkeyRecorderRulesTests: XCTestCase {
    let cmdShift = HotkeyRecorderRules.cocoaCommand | HotkeyRecorderRules.cocoaShift

    func testCocoaToCarbon() {
        XCTAssertEqual(HotkeyRecorderRules.carbonModifiers(fromCocoa: cmdShift), 768)
        XCTAssertEqual(HotkeyRecorderRules.carbonModifiers(fromCocoa: HotkeyRecorderRules.cocoaControl | HotkeyRecorderRules.cocoaOption),
                       CarbonModifier.control | CarbonModifier.option)
        // Caps Lock (1 << 16) and device bits are ignored.
        XCTAssertEqual(HotkeyRecorderRules.carbonModifiers(fromCocoa: 1 << 16 | 0x100), 0)
    }

    func testAcceptsDansAreaCombo() {
        XCTAssertEqual(HotkeyRecorderRules.evaluate(keyCode: 21, cocoaModifiers: cmdShift),
                       .accept(HotkeySpec(carbonKey: 21, carbonModifiers: 768)))
    }

    func testEscCancelsDeleteClears() {
        XCTAssertEqual(HotkeyRecorderRules.evaluate(keyCode: 53, cocoaModifiers: 0), .cancel)
        XCTAssertEqual(HotkeyRecorderRules.evaluate(keyCode: 51, cocoaModifiers: 0), .clear)
    }

    func testRejectsPlainAndShiftOnlyKeys() {
        guard case .reject = HotkeyRecorderRules.evaluate(keyCode: 0, cocoaModifiers: 0) else { return XCTFail() }
        guard case .reject = HotkeyRecorderRules.evaluate(keyCode: 0, cocoaModifiers: HotkeyRecorderRules.cocoaShift) else { return XCTFail() }
        guard case .reject = HotkeyRecorderRules.evaluate(keyCode: 56, cocoaModifiers: HotkeyRecorderRules.cocoaShift) else { return XCTFail() }
    }

    func testFunctionKeyAloneIsAllowed() {
        XCTAssertEqual(HotkeyRecorderRules.evaluate(keyCode: 122, cocoaModifiers: 0),
                       .accept(HotkeySpec(carbonKey: 122, carbonModifiers: 0)))
    }
}
