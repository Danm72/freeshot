import XCTest
@testable import FreeShotCore

final class HotkeySpecTests: XCTestCase {
    func testDecodeCleanShotDataBlob() {
        let data = Data(#"{"carbonModifiers":768,"carbonKey":21}"#.utf8)
        XCTAssertEqual(HotkeySpec.decodeCleanShot(data), HotkeySpec(carbonKey: 21, carbonModifiers: 768))
    }

    func testDecodeStringAndGarbage() {
        XCTAssertEqual(HotkeySpec.decodeCleanShot(#"{"carbonModifiers":768,"carbonKey":20}"#)?.carbonKey, 20)
        XCTAssertNil(HotkeySpec.decodeCleanShot(Data("nope".utf8)))
        XCTAssertNil(HotkeySpec.decodeCleanShot(42))
        XCTAssertNil(HotkeySpec.decodeCleanShot(nil))
    }

    func testCleanShotKeyMapping() {
        let prefs: [String: Any] = [
            "LAVAtakeAllInOne": Data(#"{"carbonModifiers":768,"carbonKey":23}"#.utf8),
            "LAVAtakeArea": Data(#"{"carbonModifiers":768,"carbonKey":21}"#.utf8),
            "LAVAtakeFullscreen": Data(#"{"carbonModifiers":768,"carbonKey":20}"#.utf8),
            "unrelated": Data("x".utf8),
        ]
        let map = CleanShotImport.decode(prefs)
        XCTAssertEqual(map, CleanShotImport.builtInDefaults)
        XCTAssertEqual(map[.area]?.displayString, "⇧⌘4")
    }

    func testBuiltInsMatchDansConfig() {
        let d = CleanShotImport.builtInDefaults
        XCTAssertEqual(CarbonModifier.command | CarbonModifier.shift, 768)
        XCTAssertEqual(d[.fullscreen], HotkeySpec(carbonKey: 20, carbonModifiers: 768))
        XCTAssertEqual(d[.area], HotkeySpec(carbonKey: 21, carbonModifiers: 768))
        XCTAssertEqual(d[.allInOne], HotkeySpec(carbonKey: 23, carbonModifiers: 768))
        XCTAssertEqual(d.count, 3)
    }

    func testHotkeysFromSuiteFallsBackWhenEmpty() {
        let suite = "freeshot.test.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suite)!
        defer { ud.removePersistentDomain(forName: suite) }
        XCTAssertEqual(CleanShotImport.hotkeys(from: ud), CleanShotImport.builtInDefaults)
        XCTAssertEqual(CleanShotImport.hotkeys(from: nil), CleanShotImport.builtInDefaults)
    }

    func testHotkeysFromSuiteReadsCustomValue() {
        let suite = "freeshot.test.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suite)!
        defer { ud.removePersistentDomain(forName: suite) }
        // ⌥⌘A for area.
        ud.set(Data(#"{"carbonModifiers":2304,"carbonKey":0}"#.utf8), forKey: "LAVAtakeArea")
        let map = CleanShotImport.hotkeys(from: ud)
        XCTAssertEqual(map, [.area: HotkeySpec(carbonKey: 0, carbonModifiers: 2304)])
        XCTAssertEqual(map[.area]?.displayString, "⌥⌘A")
    }

    func testDisplayAndMenuEquivalent() {
        let s = HotkeySpec(carbonKey: 23, carbonModifiers: CarbonModifier.control | CarbonModifier.option | CarbonModifier.shift | CarbonModifier.command)
        XCTAssertEqual(s.displayString, "⌃⌥⇧⌘5")
        XCTAssertEqual(s.menuKeyEquivalent, "5")
        XCTAssertEqual(HotkeySpec(carbonKey: 0, carbonModifiers: 0).menuKeyEquivalent, "a")
        XCTAssertEqual(HotkeySpec(carbonKey: 122, carbonModifiers: 0).keyName, "F1")
        XCTAssertEqual(HotkeySpec(carbonKey: 122, carbonModifiers: 0).menuKeyEquivalent, "")
        XCTAssertEqual(HotkeySpec(carbonKey: 200, carbonModifiers: 0).keyName, "Key200")
    }

    func testEncodedJSONRoundTripsInCleanShotShape() {
        let s = HotkeySpec(carbonKey: 21, carbonModifiers: 768)
        XCTAssertEqual(String(data: s.encodedJSON(), encoding: .utf8), #"{"carbonKey":21,"carbonModifiers":768}"#)
        XCTAssertEqual(HotkeySpec.decodeCleanShot(s.encodedJSON()), s)
    }

    func testFourCC() {
        XCTAssertEqual(fourCC("FSHT"), 0x4653_4854)
    }

    /// Reads the real CleanShot plist when this Mac has one. Skips elsewhere.
    func testLiveCleanShotPlistIfPresent() throws {
        guard let ud = UserDefaults(suiteName: CleanShotImport.suiteName),
              ud.object(forKey: "LAVAtakeArea") != nil else { throw XCTSkip("no CleanShot plist") }
        let map = CleanShotImport.hotkeys(from: ud)
        XCTAssertNotNil(map[.area])
    }
}
