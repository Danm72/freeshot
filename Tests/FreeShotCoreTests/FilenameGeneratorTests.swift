import XCTest
@testable import FreeShotCore

final class FilenameGeneratorTests: XCTestCase {
    let dublin = TimeZone(identifier: "Europe/Dublin")!
    // 2026-10-02 09:21:18 UTC = 10:21:18 Irish Summer Time.
    let date = Date(timeIntervalSince1970: 1_790_932_878)

    func testRetinaScreenshotName() {
        let g = FilenameGenerator(timeZone: dublin)
        XCTAssertEqual(g.baseName(kind: .screenshot(scale: 2), date: date), "Screenshot 2026-10-02 at 10.21.18@2x.png")
    }

    func testNonRetinaHasNoSuffix() {
        let g = FilenameGenerator(timeZone: dublin)
        XCTAssertEqual(g.baseName(kind: .screenshot(scale: 1), date: date), "Screenshot 2026-10-02 at 10.21.18.png")
    }

    func testRecordingName() {
        let g = FilenameGenerator(timeZone: dublin)
        XCTAssertEqual(g.baseName(kind: .recording, date: date), "Screen Recording 2026-10-02 at 10.21.18.mp4")
    }

    func testUsesLocalTimeNot12Hour() {
        let g = FilenameGenerator(timeZone: TimeZone(identifier: "UTC")!)
        let evening = Date(timeIntervalSince1970: 1_790_967_600) // 19:00:00 UTC
        XCTAssertEqual(g.timestamp(evening), "2026-10-02 at 19.00.00")
    }

    func testCollisionSuffixAfterScale() {
        let g = FilenameGenerator(timeZone: dublin)
        let folder = URL(fileURLWithPath: "/tmp/shots")
        var taken: Set<String> = []
        let first = g.uniqueURL(in: folder, kind: .screenshot(scale: 2), date: date) { taken.contains($0.lastPathComponent) }
        XCTAssertEqual(first.lastPathComponent, "Screenshot 2026-10-02 at 10.21.18@2x.png")
        taken.insert(first.lastPathComponent)
        let second = g.uniqueURL(in: folder, kind: .screenshot(scale: 2), date: date) { taken.contains($0.lastPathComponent) }
        XCTAssertEqual(second.lastPathComponent, "Screenshot 2026-10-02 at 10.21.18@2x (2).png")
        taken.insert(second.lastPathComponent)
        let third = g.uniqueURL(in: folder, kind: .screenshot(scale: 2), date: date) { taken.contains($0.lastPathComponent) }
        XCTAssertEqual(third.lastPathComponent, "Screenshot 2026-10-02 at 10.21.18@2x (3).png")
        XCTAssertEqual(third.deletingLastPathComponent().path, "/tmp/shots")
    }

    func testCollisionAgainstRealFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let g = FilenameGenerator(timeZone: dublin)
        let a = g.uniqueURL(in: dir, kind: .recording, date: date)
        try Data().write(to: a)
        let b = g.uniqueURL(in: dir, kind: .recording, date: date)
        XCTAssertEqual(b.lastPathComponent, "Screen Recording 2026-10-02 at 10.21.18 (2).mp4")
    }
}
