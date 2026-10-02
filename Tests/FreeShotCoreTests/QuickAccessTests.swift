import XCTest
@testable import FreeShotCore

final class QuickAccessLayoutTests: XCTestCase {
    func testBottomLeftStacksUpward() {
        let layout = QuickAccessLayout(corner: .bottomLeft, margin: 20, spacing: 12)
        let visible = CGRect(x: 0, y: 25, width: 1512, height: 920)
        let sizes = [CGSize(width: 240, height: 150), CGSize(width: 200, height: 100)]
        let f = layout.frames(for: sizes, in: visible)
        XCTAssertEqual(f[0], CGRect(x: 20, y: 45, width: 240, height: 150))
        XCTAssertEqual(f[1], CGRect(x: 20, y: 45 + 150 + 12, width: 200, height: 100))
    }

    func testSecondaryDisplayWithOffsetOrigin() {
        let layout = QuickAccessLayout(corner: .bottomLeft)
        let visible = CGRect(x: -1920, y: -1080, width: 1920, height: 1055)
        let f = layout.frames(for: [CGSize(width: 240, height: 150)], in: visible)
        XCTAssertEqual(f[0], CGRect(x: -1900, y: -1060, width: 240, height: 150))
    }

    func testBottomRightAlignsToRightEdge() {
        let layout = QuickAccessLayout(corner: .bottomRight, margin: 20)
        let visible = CGRect(x: 1512, y: 0, width: 2560, height: 1415)
        let f = layout.frames(for: [CGSize(width: 240, height: 150)], in: visible)
        XCTAssertEqual(f[0]?.maxX, 1512 + 2560 - 20)
        XCTAssertEqual(f[0]?.minY, 20)
    }

    func testOverflowCardsGetNoFrame() {
        let layout = QuickAccessLayout(margin: 20, spacing: 12)
        let visible = CGRect(x: 0, y: 0, width: 800, height: 400)
        let sizes = Array(repeating: CGSize(width: 240, height: 150), count: 4)
        let f = layout.frames(for: sizes, in: visible)
        XCTAssertNotNil(f[0])
        XCTAssertNotNil(f[1])   // 20+150+12+150 = 332 <= 380
        XCTAssertNil(f[2])
        XCTAssertNil(f[3])
    }

    func testFirstCardAlwaysGetsAFrame() {
        let f = QuickAccessLayout().frames(for: [CGSize(width: 240, height: 500)], in: CGRect(x: 0, y: 0, width: 300, height: 300))
        XCTAssertNotNil(f[0])
    }

    func testCardSizeKeepsAspectWithinMedium() {
        let wide = QuickAccessLayout.cardSize(forImagePoints: CGSize(width: 1512, height: 982))
        XCTAssertEqual(wide.width, 240)
        XCTAssertEqual(wide.height, (982 * 240 / 1512).rounded())
        let tall = QuickAccessLayout.cardSize(forImagePoints: CGSize(width: 400, height: 1200))
        XCTAssertEqual(tall.height, 170)
        XCTAssertEqual(tall.width, 150) // 57 wide clamps to the minimum
        let tiny = QuickAccessLayout.cardSize(forImagePoints: CGSize(width: 20, height: 10))
        XCTAssertEqual(tiny.width, 240)
    }
}

final class QuickAccessAutoCloseTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testExpiresAfterDuration() {
        let c = QuickAccessAutoClose(duration: 10, now: t0)
        XCTAssertFalse(c.isExpired(now: t0.addingTimeInterval(9.9)))
        XCTAssertTrue(c.isExpired(now: t0.addingTimeInterval(10)))
        XCTAssertEqual(c.remaining(now: t0.addingTimeInterval(4)), 6)
    }

    func testHoverPausesAndLeaveRestartsFullCountdown() {
        var c = QuickAccessAutoClose(duration: 10, now: t0)
        c.pause()
        XCTAssertFalse(c.isExpired(now: t0.addingTimeInterval(60)))
        XCTAssertNil(c.remaining(now: t0.addingTimeInterval(60)))
        c.resume(now: t0.addingTimeInterval(60))
        XCTAssertFalse(c.isExpired(now: t0.addingTimeInterval(69)))
        XCTAssertTrue(c.isExpired(now: t0.addingTimeInterval(70)))
    }

    func testZeroDurationNeverCloses() {
        var c = QuickAccessAutoClose(duration: 0, now: t0)
        XCTAssertFalse(c.isExpired(now: t0.addingTimeInterval(1_000)))
        c.resume(now: t0)
        XCTAssertFalse(c.isExpired(now: t0.addingTimeInterval(1_000)))
    }
}

final class CapturePlanTests: XCTestCase {
    let date = Date(timeIntervalSince1970: 1_790_000_000)
    let save = URL(fileURLWithPath: "/Users/dan/screenshots", isDirectory: true)
    let temp = URL(fileURLWithPath: "/tmp/FreeShotTest", isDirectory: true)
    let names = FilenameGenerator(timeZone: TimeZone(identifier: "Europe/Dublin")!)

    func opts(save s: Bool = true, copy c: Bool = true, overlay o: Bool = true) -> CapturePlan.Options {
        .init(save: s, copy: c, overlay: o, saveFolder: save, tempFolder: temp)
    }

    func testDefaultScreenshotSavesCopiesAndShows() {
        let p = CapturePlan.make(kind: .screenshot, scale: 2, date: date, options: opts(), names: names, exists: { _ in false })
        XCTAssertEqual(p.fileURL?.deletingLastPathComponent().path, save.path)
        XCTAssertTrue(p.fileURL!.lastPathComponent.hasPrefix("Screenshot "))
        XCTAssertTrue(p.fileURL!.lastPathComponent.hasSuffix("@2x.png"))
        XCTAssertFalse(p.isTemporary)
        XCTAssertTrue(p.addToHistory)
        XCTAssertEqual(p.copy, .image)
        XCTAssertTrue(p.showOverlay)
    }

    func testSaveOffOverlayOnUsesTempFileOutsideHistory() {
        let p = CapturePlan.make(kind: .screenshot, scale: 1, date: date, options: opts(save: false), names: names, exists: { _ in false })
        XCTAssertEqual(p.fileURL?.deletingLastPathComponent().path, temp.path)
        XCTAssertTrue(p.isTemporary)
        XCTAssertFalse(p.addToHistory)
    }

    func testCopyOnlyNeedsNoFile() {
        let p = CapturePlan.make(kind: .screenshot, scale: 2, date: date, options: opts(save: false, overlay: false), names: names)
        XCTAssertNil(p.fileURL)
        XCTAssertEqual(p.copy, .image)
        XCTAssertFalse(p.showOverlay)
    }

    func testCollisionGetsSuffix() {
        let first = names.uniqueURL(in: save, kind: .screenshot(scale: 2), date: date, exists: { _ in false })
        let p = CapturePlan.make(kind: .screenshot, scale: 2, date: date, options: opts(), names: names, exists: { $0 == first })
        XCTAssertTrue(p.fileURL!.lastPathComponent.hasSuffix("@2x (2).png"))
    }

    func testRecordingInSaveFolderStaysPut() {
        let src = save.appendingPathComponent("Screen Recording 2026-10-02 at 10.21.18.mp4")
        let p = CapturePlan.make(kind: .recording(src), scale: 2, date: date, options: opts(), names: names, exists: { _ in false })
        XCTAssertEqual(p.fileURL, src)
        XCTAssertNil(p.moveFrom)
        XCTAssertTrue(p.addToHistory)
        XCTAssertEqual(p.copy, .fileURL)
    }

    func testRecordingElsewhereMovesIntoSaveFolder() {
        let src = URL(fileURLWithPath: "/tmp/rec-123.mp4")
        let p = CapturePlan.make(kind: .recording(src), scale: 2, date: date, options: opts(), names: names, exists: { _ in false })
        XCTAssertEqual(p.moveFrom, src)
        XCTAssertEqual(p.fileURL?.deletingLastPathComponent().path, save.path)
        XCTAssertTrue(p.fileURL!.lastPathComponent.hasPrefix("Screen Recording "))
        XCTAssertEqual(p.fileURL!.pathExtension, "mp4")
    }

    func testRecordingWithSaveOffStaysAndIsTemporary() {
        let src = URL(fileURLWithPath: "/tmp/rec-123.mp4")
        let p = CapturePlan.make(kind: .recording(src), scale: 2, date: date, options: opts(save: false), names: names)
        XCTAssertEqual(p.fileURL, src)
        XCTAssertNil(p.moveFrom)
        XCTAssertTrue(p.isTemporary)
        XCTAssertFalse(p.addToHistory)
    }

    func testIsInsideHandlesTrailingSlash() {
        XCTAssertTrue(CapturePlan.isInside(URL(fileURLWithPath: "/a/b/c.png"), folder: URL(fileURLWithPath: "/a/b/")))
        XCTAssertFalse(CapturePlan.isInside(URL(fileURLWithPath: "/a/b/d/c.png"), folder: URL(fileURLWithPath: "/a/b")))
    }
}
