import XCTest
@testable import FreeShotCore

final class CoordinateSpaceTests: XCTestCase {
    // Primary: 1512×982 @2x (MacBook). Secondary: 1920×1080 @1x to the left and higher,
    // so its Cocoa origin is negative x and positive y.
    let primary = DisplayDescriptor(id: 1, cocoaFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), scale: 2)
    let left = DisplayDescriptor(id: 2, cocoaFrame: CGRect(x: -1920, y: 200, width: 1920, height: 1080), scale: 1)
    // A third display below the primary: negative Cocoa y.
    let below = DisplayDescriptor(id: 3, cocoaFrame: CGRect(x: 0, y: -1080, width: 1920, height: 1080), scale: 1)

    var space: CoordinateSpace { CoordinateSpace(displays: [left, primary, below]) }

    func testPrimaryDetection() {
        XCTAssertEqual(space.primary?.id, 1)
    }

    func testPointRoundTrip() {
        let p = CGPoint(x: -100, y: 1000)
        let cg = space.cgPoint(fromCocoa: p)
        XCTAssertEqual(cg, CGPoint(x: -100, y: -18))
        XCTAssertEqual(space.cocoaPoint(fromCG: cg), p)
    }

    func testCGBoundsOfDisplays() {
        XCTAssertEqual(space.cgBounds(of: primary), CGRect(x: 0, y: 0, width: 1512, height: 982))
        // Left display top edge sits 1280 up in Cocoa = 982 - 1280 = -298 in CG.
        XCTAssertEqual(space.cgBounds(of: left), CGRect(x: -1920, y: -298, width: 1920, height: 1080))
        XCTAssertEqual(space.cgBounds(of: below), CGRect(x: 0, y: 982, width: 1920, height: 1080))
    }

    func testRectRoundTrip() {
        let r = CGRect(x: -500, y: 300, width: 200, height: 100)
        XCTAssertEqual(space.cocoaRect(fromCG: space.cgRect(fromCocoa: r)), r)
    }

    func testDisplayLookup() {
        XCTAssertEqual(space.display(containingCocoa: CGPoint(x: 10, y: 10))?.id, 1)
        XCTAssertEqual(space.display(containingCocoa: CGPoint(x: -10, y: 500))?.id, 2)
        XCTAssertEqual(space.display(containingCocoa: CGPoint(x: 100, y: -500))?.id, 3)
        XCTAssertNil(space.display(containingCocoa: CGPoint(x: -10, y: 0)))
        // Cursor parked on the top edge of the primary still counts.
        XCTAssertEqual(space.display(containingCocoa: CGPoint(x: 700, y: 982))?.id, 1)
        XCTAssertEqual(space.display(containingCG: CGPoint(x: 100, y: 1500))?.id, 3)
        XCTAssertEqual(space.display(id: 2), left)
    }

    func testBestDisplayForSpanningRect() {
        let r = CGRect(x: -100, y: 400, width: 400, height: 100) // 100 on left, 300 on primary
        XCTAssertEqual(space.display(bestFor: r)?.id, 1)
        XCTAssertNil(space.display(bestFor: CGRect(x: 5000, y: 5000, width: 10, height: 10)))
    }

    func testLocalPixelsOnRetina() {
        // 100×50 point rect whose Cocoa bottom-left is (10, 900) -> top-left local (10, 32).
        let r = CGRect(x: 10, y: 900, width: 100, height: 50)
        XCTAssertEqual(space.localTopLeftPoints(fromCocoa: r, on: primary), CGRect(x: 10, y: 32, width: 100, height: 50))
        XCTAssertEqual(space.localPixels(fromCocoa: r, on: primary), CGRect(x: 20, y: 64, width: 200, height: 100))
    }

    func testLocalPixelsOnNegativeOriginDisplay() {
        // Top-left corner of the left display: Cocoa y top = 1280.
        let r = CGRect(x: -1920, y: 1180, width: 300, height: 100)
        XCTAssertEqual(space.localPixels(fromCocoa: r, on: left), CGRect(x: 0, y: 0, width: 300, height: 100))
        let back = space.cocoaRect(fromLocalTopLeft: CGRect(x: 0, y: 0, width: 300, height: 100), on: left)
        XCTAssertEqual(back, r)
    }

    func testLocalPixelsClampAndRound() {
        let r = CGRect(x: 1500.3, y: -10, width: 50, height: 20.2)
        let px = space.localPixels(fromCocoa: r, on: primary)
        XCTAssertEqual(px.maxX, 3024)
        XCTAssertEqual(px.maxY, 1964)
        XCTAssertEqual(px.minX, 3000)
        XCTAssertEqual(space.localPixels(fromCocoa: CGRect(x: 4000, y: 0, width: 10, height: 10), on: primary), .zero)
    }

    func testSelectionRectAnyDirection() {
        let s = CGPoint(x: 100, y: 100)
        XCTAssertEqual(SelectionMath.rect(from: s, to: CGPoint(x: 50, y: 160)), CGRect(x: 50, y: 100, width: 50, height: 60))
        XCTAssertEqual(SelectionMath.sizeLabel(for: CGRect(x: 0, y: 0, width: 320, height: 240.4), scale: 2), "640 × 481")
    }

    func testAxisLockKeepsHeightWhenPointerMovesSideways() {
        // Drag 400 x 300, press Shift, move right: the height stays 300, it never collapses.
        let start = CGPoint(x: 100, y: 100)
        var lock = AxisLock(anchor: CGPoint(x: 500, y: 400))
        let end = lock.end(for: CGPoint(x: 600, y: 390))
        XCTAssertEqual(lock.axis, .horizontal)
        XCTAssertEqual(SelectionMath.rect(from: start, to: end), CGRect(x: 100, y: 100, width: 500, height: 300))
    }

    func testAxisLockKeepsWidthWhenPointerMovesVertically() {
        let start = CGPoint(x: 100, y: 100)
        var lock = AxisLock(anchor: CGPoint(x: 500, y: 400))
        let end = lock.end(for: CGPoint(x: 505, y: 200))
        XCTAssertEqual(lock.axis, .vertical)
        XCTAssertEqual(SelectionMath.rect(from: start, to: end), CGRect(x: 100, y: 100, width: 400, height: 100))
    }

    func testAxisLockChoiceSticksAndWaitsForClearMove() {
        var lock = AxisLock(anchor: CGPoint(x: 500, y: 400))
        // Under the threshold: nothing is chosen and the end stays at the anchor.
        XCTAssertEqual(lock.end(for: CGPoint(x: 501, y: 401)), CGPoint(x: 500, y: 400))
        XCTAssertNil(lock.axis)
        _ = lock.end(for: CGPoint(x: 520, y: 405))
        XCTAssertEqual(lock.axis, .horizontal)
        // A later vertical move does not flip the free axis.
        XCTAssertEqual(lock.end(for: CGPoint(x: 530, y: 900)), CGPoint(x: 530, y: 400))
    }

    func testAxisLockShiftMovesAnchor() {
        var lock = AxisLock(anchor: CGPoint(x: 10, y: 10))
        lock.shift(by: CGVector(dx: 5, dy: -3))
        XCTAssertEqual(lock.anchor, CGPoint(x: 15, y: 7))
    }
}
