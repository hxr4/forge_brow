import Foundation

enum Storage {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = base.appendingPathComponent("Forge Browser", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        let url = directory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }
}

struct HistoryEntry: Codable, Equatable {
    let url: String
    var title: String
    var visitedAt: Date
}

final class HistoryStore {
    static let shared = HistoryStore()

    private let fileName = "history.json"
    private let limit = 6000
    private var entries: [HistoryEntry]
    private var dirty = false
    private(set) var revision = 0

    private init() {
        entries = Storage.load([HistoryEntry].self, from: fileName) ?? []
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in self?.flush() }
        RunLoop.main.add(timer, forMode: .common)
    }

    var all: [HistoryEntry] { entries }

    func record(url: String, title: String) {
        guard url.hasPrefix("http://") || url.hasPrefix("https://") else { return }
        if let index = entries.firstIndex(where: { $0.url == url }) {
            entries[index].visitedAt = Date()
            if !title.isEmpty { entries[index].title = title }
            let entry = entries.remove(at: index)
            entries.insert(entry, at: 0)
        } else {
            entries.insert(HistoryEntry(url: url, title: title, visitedAt: Date()), at: 0)
            if entries.count > limit { entries.removeLast(entries.count - limit) }
        }
        dirty = true
        revision += 1
    }

    func recent(_ count: Int) -> [HistoryEntry] { Array(entries.prefix(count)) }

    func search(_ query: String, limit: Int = 200) -> [HistoryEntry] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return Array(entries.prefix(limit)) }
        return entries.filter {
            $0.title.lowercased().contains(needle) || $0.url.lowercased().contains(needle)
        }.prefix(limit).map { $0 }
    }

    func clear() {
        entries.removeAll()
        dirty = true
        revision += 1
        flush()
    }

    func flush() {
        guard dirty else { return }
        Storage.save(entries, to: fileName)
        dirty = false
    }
}

struct Bookmark: Codable, Equatable {
    var title: String
    var url: String
    var addedAt: Date
}

final class BookmarkStore {
    static let shared = BookmarkStore()

    private let fileName = "bookmarks.json"
    private(set) var all: [Bookmark]
    private(set) var revision = 0

    private init() {
        all = Storage.load([Bookmark].self, from: fileName) ?? []
    }

    func contains(url: String) -> Bool { all.contains { $0.url == url } }

    @discardableResult
    func toggle(title: String, url: String) -> Bool {
        if let index = all.firstIndex(where: { $0.url == url }) {
            all.remove(at: index)
            persist()
            return false
        }
        all.insert(Bookmark(title: title.isEmpty ? url : title, url: url, addedAt: Date()), at: 0)
        persist()
        return true
    }

    func remove(url: String) {
        all.removeAll { $0.url == url }
        persist()
    }

    private func persist() {
        revision += 1
        Storage.save(all, to: fileName)
    }
}

struct ClosedTab {
    let url: String
    let title: String
}

final class ClosedTabStore {
    static let shared = ClosedTabStore()
    private var stack: [ClosedTab] = []

    func push(url: String, title: String) {
        guard !url.isEmpty, url != "forge://home/" else { return }
        stack.append(ClosedTab(url: url, title: title))
        if stack.count > 40 { stack.removeFirst() }
    }

    func pop() -> ClosedTab? { stack.popLast() }
    var recent: [ClosedTab] { stack.suffix(10).reversed() }
}
