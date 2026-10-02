import CoreGraphics
import XCTest
@testable import FreeShotCore

final class CaptureGeometryTests: XCTestCase {

    // MARK: Selection

    func testSelectionPlainDragAnyDirection() {
        let r = CaptureGeometry.selection(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 40, y: 160))
        XCTAssertEqual(r, CGRect(x: 40, y: 100, width: 60, height: 60))
    }

    func testSelectionShiftLocksToLargerAxis() {
        let r = CaptureGeometry.selection(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 50, y: 10), lockAxis: true)
        XCTAssertEqual(r, CGRect(x: 0, y: 0, width: 50, height: 0))
    }

    func testSelectionFromCenter() {
        let r = CaptureGeometry.selection(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 130, y: 80), fromCenter: true)
        XCTAssertEqual(r, CGRect(x: 70, y: 80, width: 60, height: 40))
    }

    func testClampKeepsEdges() {
        let b = CGRect(x: 0, y: 0, width: 100, height: 50)
        XCTAssertEqual(CaptureGeometry.clamp(CGPoint(x: 120, y: -5), to: b), CGPoint(x: 100, y: 0))
        XCTAssertEqual(CaptureGeometry.clamp(CGPoint(x: 30, y: 20), to: b), CGPoint(x: 30, y: 20))
    }

    func testPixelAlignedSnapsToHalfPointsAtRetina() {
        let r = CaptureGeometry.pixelAligned(CGRect(x: 10.3, y: 20.8, width: 5.1, height: 4.0), scale: 2)
        XCTAssertEqual(r, CGRect(x: 10.5, y: 21.0, width: 5.0, height: 4.0))
    }

    func testIsClick() {
        XCTAssertTrue(CaptureGeometry.isClick(CGRect(x: 0, y: 0, width: 2, height: 1)))
        XCTAssertFalse(CaptureGeometry.isClick(CGRect(x: 0, y: 0, width: 2, height: 30)))
    }

    func testMoveStaysInBounds() {
        let b = CGRect(x: 0, y: 0, width: 100, height: 100)
        let r = CaptureGeometry.move(CGRect(x: 80, y: 10, width: 15, height: 10), by: CGVector(dx: 20, dy: -30), within: b)
        XCTAssertEqual(r, CGRect(x: 85, y: 0, width: 15, height: 10))
    }

    // MARK: Nudge

    func testArrowKeyCodes() {
        XCTAssertEqual(CaptureGeometry.arrow(forKeyCode: 123), .left)
        XCTAssertEqual(CaptureGeometry.arrow(forKeyCode: 126), .up)
        XCTAssertNil(CaptureGeometry.arrow(forKeyCode: 49))
    }

    func testNudgeIsYUpAndShiftTimesTen() {
        XCTAssertEqual(CaptureGeometry.nudge(.up, shift: false), CGVector(dx: 0, dy: 1))
        XCTAssertEqual(CaptureGeometry.nudge(.down, shift: true), CGVector(dx: 0, dy: -10))
        XCTAssertEqual(CaptureGeometry.nudge(.left, shift: false), CGVector(dx: -1, dy: 0))
    }

    // MARK: Magnifier

    func testMagnifierSourceIsOddAndCentred() {
        let r = CaptureGeometry.magnifierSourcePixels(cursorLocalTopLeft: CGPoint(x: 100.4, y: 50.7), scale: 2, pixelsAcross: 20)
        // Cursor pixel (200, 101); 21 across, 10 either side.
        XCTAssertEqual(r, CGRect(x: 190, y: 91, width: 21, height: 21))
    }

    func testPlaceBesideDefaultsBelowRight() {
        let b = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let r = CaptureGeometry.placeBeside(cursor: CGPoint(x: 100, y: 400), size: CGSize(width: 120, height: 140), offset: 20, in: b)
        XCTAssertEqual(r, CGRect(x: 120, y: 240, width: 120, height: 140))
    }

    func testPlaceBesideFlipsAtRightAndBottomEdges() {
        let b = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let r = CaptureGeometry.placeBeside(cursor: CGPoint(x: 950, y: 50), size: CGSize(width: 120, height: 140), offset: 20, in: b)
        XCTAssertEqual(r, CGRect(x: 810, y: 70, width: 120, height: 140))
    }

    func testPlaceBesideOnSecondaryDisplayWithNegativeOrigin() {
        let b = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let r = CaptureGeometry.placeBeside(cursor: CGPoint(x: -10, y: 500), size: CGSize(width: 100, height: 100), offset: 10, in: b)
        XCTAssertEqual(r.minX, -120)
        XCTAssertTrue(b.contains(r))
    }

    func testSizeLabelGoesInsideWhenNoRoomBelow() {
        let b = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let below = CaptureGeometry.sizeLabelFrame(for: CGRect(x: 100, y: 300, width: 50, height: 50),
                                                   labelSize: CGSize(width: 80, height: 22), gap: 6, in: b)
        XCTAssertEqual(below.origin, CGPoint(x: 100, y: 272))
        let inside = CaptureGeometry.sizeLabelFrame(for: CGRect(x: 100, y: 5, width: 50, height: 50),
                                                    labelSize: CGSize(width: 80, height: 22), gap: 6, in: b)
        XCTAssertEqual(inside.origin, CGPoint(x: 100, y: 11))
    }

    func testCoordinateLabel() {
        XCTAssertEqual(CaptureGeometry.coordinateLabel(cursorLocalTopLeft: CGPoint(x: 12.9, y: 400.2)), "12, 400")
    }

    // MARK: Window picking

    func testPickableWindowParsesCGInfo() {
        let info: [String: Any] = [
            "kCGWindowNumber": NSNumber(value: 42),
            "kCGWindowBounds": ["X": NSNumber(value: 10), "Y": NSNumber(value: 20),
                                "Width": NSNumber(value: 300), "Height": NSNumber(value: 200)],
            "kCGWindowLayer": NSNumber(value: 0),
            "kCGWindowOwnerPID": NSNumber(value: 99),
            "kCGWindowOwnerName": "Safari",
        ]
        let w = PickableWindow(cgInfo: info)
        XCTAssertEqual(w?.windowID, 42)
        XCTAssertEqual(w?.cgFrame, CGRect(x: 10, y: 20, width: 300, height: 200))
        XCTAssertEqual(w?.ownerName, "Safari")
        XCTAssertNil(PickableWindow(cgInfo: ["kCGWindowNumber": NSNumber(value: 1)]))
    }

    func testHitTestPicksFrontMostAndSkipsOwnAndMenuBar() {
        let all = [
            PickableWindow(windowID: 1, cgFrame: CGRect(x: 0, y: 0, width: 2000, height: 30), layer: 24, ownerPID: 5),
            PickableWindow(windowID: 2, cgFrame: CGRect(x: 0, y: 0, width: 2000, height: 2000), layer: 0, ownerPID: 777),
            PickableWindow(windowID: 3, cgFrame: CGRect(x: 100, y: 100, width: 400, height: 300), layer: 0, ownerPID: 6),
            PickableWindow(windowID: 4, cgFrame: CGRect(x: 0, y: 0, width: 1500, height: 900), layer: 0, ownerPID: 7),
            PickableWindow(windowID: 5, cgFrame: CGRect(x: 0, y: 0, width: 5, height: 5), layer: 0, ownerPID: 8),
        ]
        let picks = WindowHitTest.pickable(all, excludingPID: 777)
        XCTAssertEqual(picks.map(\.windowID), [3, 4])
        XCTAssertEqual(WindowHitTest.window(at: CGPoint(x: 150, y: 150), in: picks)?.windowID, 3)
        XCTAssertEqual(WindowHitTest.window(at: CGPoint(x: 10, y: 10), in: picks)?.windowID, 4)
        XCTAssertNil(WindowHitTest.window(at: CGPoint(x: 1600, y: 10), in: picks))
    }

    func testCaptureSizeFitsAcceptsShadowRejectsParentWindow() {
        let frame = CGSize(width: 320, height: 238)
        // Exact, no shadow.
        XCTAssertTrue(WindowHitTest.captureSizeFits(pixelSize: CGSize(width: 640, height: 476), frame: frame, scale: 2))
        // macOS 26 shadow pad of 68 pt per axis.
        XCTAssertTrue(WindowHitTest.captureSizeFits(pixelSize: CGSize(width: 776, height: 612), frame: frame, scale: 2))
        // Measured live: a child sheet came back as its 1512x949 parent plus shadow.
        XCTAssertFalse(WindowHitTest.captureSizeFits(pixelSize: CGSize(width: 3160, height: 2034), frame: frame, scale: 2))
    }

    // MARK: All-in-One + timer

    func testAllInOneShortcuts() {
        XCTAssertEqual(AllInOneMode.from(character: "1"), .area)
        XCTAssertEqual(AllInOneMode.from(character: "7"), .record)
        XCTAssertEqual(AllInOneMode.from(character: "w"), .window)
        XCTAssertEqual(AllInOneMode.from(character: "O"), .text)
        XCTAssertNil(AllInOneMode.from(character: "8"))
        XCTAssertNil(AllInOneMode.from(character: "ab"))
        XCTAssertEqual(AllInOneMode.allCases.count, 7)
        XCTAssertEqual(Set(AllInOneMode.allCases.map(\.letter)).count, 7)
    }

    func testCountdown() {
        XCTAssertEqual(SelfTimerMath.countdown(from: SelfTimerMath.defaultSeconds), [5, 4, 3, 2, 1])
        XCTAssertEqual(SelfTimerMath.countdown(from: 0), [])
    }
}
