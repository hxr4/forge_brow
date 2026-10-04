import AppKit
import Foundation

struct SessionTab: Codable {
    var url: String
    var title: String
    var groupID: String?
}

struct SessionGroup: Codable {
    var id: String
    var name: String
    var colorIndex: Int
    var isCollapsed: Bool
}

struct SessionWindow: Codable {
    var frame: [Double]
    var tabs: [SessionTab]
    var groups: [SessionGroup]
    var selectedIndex: Int
}

struct SessionSnapshot: Codable {
    var version: Int
    var savedAt: Date
    var windows: [SessionWindow]
}

final class SessionStore {
    static let shared = SessionStore()

    private let fileName = "session.json"
    private let recoveredName = "session-recovered.json"
    private let runningMarker = "running.marker"
    private let restoringMarker = "restoring.marker"
    private let currentVersion = 1

    private let queue = DispatchQueue(label: "com.forge.session", qos: .utility)
    private var pending: DispatchWorkItem?
    private var lastWritten: Data?

    private var url: URL { Storage.directory.appendingPathComponent(fileName) }
    private var recoveredURL: URL { Storage.directory.appendingPathComponent(recoveredName) }
    private var runningURL: URL { Storage.directory.appendingPathComponent(runningMarker) }
    private var restoringURL: URL { Storage.directory.appendingPathComponent(restoringMarker) }

    private(set) var previousRunCrashed = false
    private(set) var previousRestoreInterrupted = false

    func inspectMarkers() {
        let manager = FileManager.default
        previousRunCrashed = manager.fileExists(atPath: runningURL.path)
        previousRestoreInterrupted = manager.fileExists(atPath: restoringURL.path)
    }

    func markLaunched() {
        try? Data().write(to: runningURL)
    }

    func markCleanExit() {
        try? FileManager.default.removeItem(at: runningURL)
    }

    func beginRestore() {
        try? Data().write(to: restoringURL)
    }

    func endRestore() {
        try? FileManager.default.removeItem(at: restoringURL)
    }

    func load() -> SessionSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(SessionSnapshot.self, from: data) else { return nil }
        guard snapshot.version == currentVersion else { return nil }
        return snapshot
    }

    func quarantineForCrashLoop() {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else { return }
        try? manager.removeItem(at: recoveredURL)
        try? manager.moveItem(at: url, to: recoveredURL)
        endRestore()
    }

    func schedule(_ builder: @escaping () -> SessionSnapshot) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            let snapshot = builder()
            self?.queue.async { self?.write(snapshot) }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    func flush(_ snapshot: SessionSnapshot) {
        pending?.cancel()
        pending = nil
        queue.sync { write(snapshot) }
    }

    private func write(_ snapshot: SessionSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        guard data != lastWritten else { return }
        do {
            try data.write(to: url, options: .atomic)
            lastWritten = data
        } catch {
            NSLog("[forge] session write failed: %@", error.localizedDescription)
        }
    }
}
