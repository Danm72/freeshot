import Foundation

public struct HistoryEntry: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case screenshot, recording }
    public var path: String
    public var date: Date
    public var kind: Kind

    public init(url: URL, date: Date = Date(), kind: Kind = .screenshot) {
        self.path = url.path
        self.date = date
        self.kind = kind
    }

    public var url: URL { URL(fileURLWithPath: path) }
}

/// Recent captures, newest first, kept in a JSON file
/// (~/Library/Application Support/FreeShot/history.json for the app).
public final class CaptureHistory: @unchecked Sendable {
    public static let defaultFileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("FreeShot/history.json")
    }()

    public let fileURL: URL
    public let limit: Int
    private let lock = NSLock()
    private var cache: [HistoryEntry]?

    public init(fileURL: URL = CaptureHistory.defaultFileURL, limit: Int = 50) {
        self.fileURL = fileURL
        self.limit = limit
    }

    public var entries: [HistoryEntry] {
        lock.lock(); defer { lock.unlock() }
        return loadLocked()
    }

    /// The newest `n` entries whose files still exist.
    public func recent(_ n: Int = 10, exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> [HistoryEntry] {
        Array(entries.filter { exists($0.url) }.prefix(n))
    }

    public func add(_ entry: HistoryEntry) {
        lock.lock(); defer { lock.unlock() }
        var list = loadLocked().filter { $0.path != entry.path }
        list.insert(entry, at: 0)
        if list.count > limit { list.removeLast(list.count - limit) }
        saveLocked(list)
    }

    public func remove(path: String) {
        lock.lock(); defer { lock.unlock() }
        saveLocked(loadLocked().filter { $0.path != path })
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        saveLocked([])
    }

    private func loadLocked() -> [HistoryEntry] {
        if let cache { return cache }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let list = (try? Data(contentsOf: fileURL)).flatMap { try? dec.decode([HistoryEntry].self, from: $0) } ?? []
        cache = list
        return list
    }

    private func saveLocked(_ list: [HistoryEntry]) {
        cache = list
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try enc.encode(list).write(to: fileURL, options: .atomic)
        } catch {
            FileHandle.standardError.write("FreeShot: history write failed: \(error)\n".data(using: .utf8)!)
        }
    }
}
