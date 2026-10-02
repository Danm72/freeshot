import XCTest
@testable import FreeShotCore

final class CaptureHistoryTests: XCTestCase {
    var file: URL!

    override func setUp() {
        file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("history.json")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

    func testAddNewestFirstDedupeAndPersist() {
        let h = CaptureHistory(fileURL: file, limit: 3)
        let base = Date(timeIntervalSince1970: 1_790_932_878)
        for i in 0..<4 { h.add(HistoryEntry(url: URL(fileURLWithPath: "/tmp/\(i).png"), date: base + Double(i))) }
        XCTAssertEqual(h.entries.map(\.path), ["/tmp/3.png", "/tmp/2.png", "/tmp/1.png"])
        h.add(HistoryEntry(url: URL(fileURLWithPath: "/tmp/1.png"), date: base + 10, kind: .recording))
        XCTAssertEqual(h.entries.map(\.path), ["/tmp/1.png", "/tmp/3.png", "/tmp/2.png"])

        let reloaded = CaptureHistory(fileURL: file, limit: 3)
        XCTAssertEqual(reloaded.entries, h.entries)
        XCTAssertEqual(reloaded.entries.first?.kind, .recording)
        XCTAssertEqual(reloaded.entries.first?.date, base + 10)
    }

    func testRecentSkipsMissingFiles() {
        let h = CaptureHistory(fileURL: file)
        h.add(HistoryEntry(url: URL(fileURLWithPath: "/tmp/a.png")))
        h.add(HistoryEntry(url: URL(fileURLWithPath: "/tmp/b.png")))
        XCTAssertEqual(h.recent(10) { $0.lastPathComponent == "a.png" }.map(\.path), ["/tmp/a.png"])
    }

    func testRemoveClearAndCorruptFile() throws {
        let h = CaptureHistory(fileURL: file)
        h.add(HistoryEntry(url: URL(fileURLWithPath: "/tmp/a.png")))
        h.remove(path: "/tmp/a.png")
        XCTAssertTrue(h.entries.isEmpty)
        h.add(HistoryEntry(url: URL(fileURLWithPath: "/tmp/b.png")))
        h.clear()
        XCTAssertTrue(CaptureHistory(fileURL: file).entries.isEmpty)
        try Data("not json".utf8).write(to: file)
        XCTAssertTrue(CaptureHistory(fileURL: file).entries.isEmpty)
    }
}
