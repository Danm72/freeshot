import XCTest
@testable import FreeShotCore

final class SettingsTests: XCTestCase {
    var suite: String!
    var ud: UserDefaults!
    var fakeCleanShot: UserDefaults?

    override func setUp() {
        suite = "freeshot.test.\(UUID().uuidString)"
        ud = UserDefaults(suiteName: suite)
        fakeCleanShot = nil
    }

    override func tearDown() {
        ud.removePersistentDomain(forName: suite)
        if let fakeCleanShot { fakeCleanShot.removePersistentDomain(forName: suite + ".cs") }
    }

    func makeSettings() -> AppSettings { AppSettings(defaults: ud, cleanShotDefaults: { self.fakeCleanShot }) }

    func testDefaultsMatchDansCleanShot() {
        let s = makeSettings()
        XCTAssertEqual(s.saveFolder.path, NSHomeDirectory() + "/screenshots")
        XCTAssertTrue(s.saveAfterCapture)
        XCTAssertTrue(s.copyAfterCapture)
        XCTAssertTrue(s.showOverlayAfterCapture)
        XCTAssertFalse(s.soundsEnabled)
        XCTAssertEqual(s.overlayAutoCloseSeconds, 10)
        XCTAssertEqual(s.overlayCorner, .bottomLeft)
        XCTAssertTrue(s.windowShadow)
        XCTAssertTrue(s.showMagnifier)
        XCTAssertTrue(s.showCrosshair)
        XCTAssertEqual(s.annotateTextSize, 30)
        XCTAssertEqual(s.pixelateIntensity, 10)
        XCTAssertEqual(s.recordFPS, 60)
        XCTAssertNil(s.lastArea)
    }

    func testValuesPersist() {
        let s = makeSettings()
        s.saveFolder = URL(fileURLWithPath: "/tmp/shots")
        s.copyAfterCapture = false
        s.overlayAutoCloseSeconds = 4
        s.overlayCorner = .bottomRight
        let again = makeSettings()
        XCTAssertEqual(again.saveFolder.path, "/tmp/shots")
        XCTAssertFalse(again.copyAfterCapture)
        XCTAssertEqual(again.overlayAutoCloseSeconds, 4)
        XCTAssertEqual(again.overlayCorner, .bottomRight)
    }

    func testHotkeysSeedFromBuiltInsWithoutCleanShot() {
        XCTAssertEqual(makeSettings().hotkeys, CleanShotImport.builtInDefaults)
        XCTAssertNotNil(ud.data(forKey: "hotkeys"), "seeded hotkeys are stored")
    }

    func testHotkeysSeedFromCleanShotPlist() {
        fakeCleanShot = UserDefaults(suiteName: suite + ".cs")
        fakeCleanShot!.set(Data(#"{"carbonModifiers":768,"carbonKey":21}"#.utf8), forKey: "LAVAtakeArea")
        XCTAssertEqual(makeSettings().hotkeys, [.area: HotkeySpec(carbonKey: 21, carbonModifiers: 768)])
    }

    func testEditedHotkeysStickAndStayUnique() {
        let s = makeSettings()
        let ocrKey = HotkeySpec(carbonKey: 2, carbonModifiers: 768) // ⇧⌘D
        s.setHotkey(ocrKey, for: .ocr)
        // Moving ⇧⌘4 to window takes it off area.
        s.setHotkey(CleanShotImport.builtInDefaults[.area], for: .window)
        let again = makeSettings().hotkeys
        XCTAssertEqual(again[.ocr], ocrKey)
        XCTAssertEqual(again[.window], HotkeySpec(carbonKey: 21, carbonModifiers: 768))
        XCTAssertNil(again[.area])
        s.setHotkey(nil, for: .ocr)
        XCTAssertNil(makeSettings().hotkeys[.ocr])
    }

    func testLastAreaRoundTrip() {
        let s = makeSettings()
        s.lastArea = StoredArea(cocoaRect: CGRect(x: -10, y: 20, width: 300, height: 200), displayID: 7)
        XCTAssertEqual(makeSettings().lastArea, StoredArea(cocoaRect: CGRect(x: -10, y: 20, width: 300, height: 200), displayID: 7))
        s.lastArea = nil
        XCTAssertNil(makeSettings().lastArea)
    }
}
