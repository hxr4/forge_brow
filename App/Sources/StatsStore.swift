import Foundation

final class StatsStore {
    static let shared = StatsStore()

    private let blockedKey = "forge.stats.lifetimeBlocked"
    private let bytesKey = "forge.stats.lifetimeBytesSaved"

    private var sessionBlockedBaseline: UInt = 0
    private var sessionBytesBaseline: UInt = 0

    private init() {}

    var lifetimeBlocked: UInt {
        get { UInt(UserDefaults.standard.integer(forKey: blockedKey)) }
        set { UserDefaults.standard.set(Int(newValue), forKey: blockedKey) }
    }

    var lifetimeBytesSaved: UInt {
        get { UInt(UserDefaults.standard.integer(forKey: bytesKey)) }
        set { UserDefaults.standard.set(Int(newValue), forKey: bytesKey) }
    }

    func commitSessionCounters(blocked: UInt, bytes: UInt) {
        guard blocked >= sessionBlockedBaseline, bytes >= sessionBytesBaseline else {
            sessionBlockedBaseline = blocked
            sessionBytesBaseline = bytes
            return
        }
        lifetimeBlocked += blocked - sessionBlockedBaseline
        lifetimeBytesSaved += bytes - sessionBytesBaseline
        sessionBlockedBaseline = blocked
        sessionBytesBaseline = bytes
    }

    static func estimatedSecondsSaved(fromBytes bytes: UInt, blockedRequests: UInt) -> Double {
        let assumedBytesPerSecond = 3_000_000.0
        let assumedLatencyPerRequest = 0.04
        return Double(bytes) / assumedBytesPerSecond + Double(blockedRequests) * assumedLatencyPerRequest
    }
}

enum Trays {
    struct Site: Codable, Equatable {
        var title: String
        var url: String
    }

    struct Tray: Codable, Equatable {
        var name: String
        var sites: [Site]
    }

    private static let key = "forge.trays"
    private static var cache: [Tray]?
    private(set) static var revision = 0

    static let defaults: [Tray] = [
        Tray(name: "Dev", sites: [
            Site(title: "GitHub", url: "https://github.com"),
            Site(title: "MDN", url: "https://developer.mozilla.org"),
            Site(title: "Stack Overflow", url: "https://stackoverflow.com"),
            Site(title: "Hacker News", url: "https://news.ycombinator.com")
        ]),
        Tray(name: "Personal", sites: [
            Site(title: "Gmail", url: "https://mail.google.com"),
            Site(title: "Calendar", url: "https://calendar.google.com"),
            Site(title: "Drive", url: "https://drive.google.com"),
            Site(title: "Notion", url: "https://notion.so")
        ]),
        Tray(name: "Entertainment", sites: [
            Site(title: "YouTube", url: "https://youtube.com"),
            Site(title: "Spotify", url: "https://open.spotify.com"),
            Site(title: "Netflix", url: "https://netflix.com"),
            Site(title: "Twitch", url: "https://twitch.tv")
        ])
    ]

    static var all: [Tray] {
        get {
            if let cache { return cache }
            guard let data = UserDefaults.standard.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([Tray].self, from: data) else {
                cache = defaults
                return defaults
            }
            cache = decoded
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: key)
            cache = newValue
            revision += 1
        }
    }
}

enum PinnedSites {
    private static let key = "forge.pinnedSites"
    private static var cache: [Site]?

    struct Site: Codable, Equatable {
        var title: String
        var url: String
    }

    static let defaults: [Site] = [
        Site(title: "GitHub", url: "https://github.com"),
        Site(title: "Hacker News", url: "https://news.ycombinator.com"),
        Site(title: "MDN", url: "https://developer.mozilla.org"),
        Site(title: "YouTube", url: "https://youtube.com")
    ]

    static var all: [Site] {
        get {
            if let cache { return cache }
            guard let data = UserDefaults.standard.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([Site].self, from: data) else {
                cache = defaults
                return defaults
            }
            cache = decoded
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: key)
            cache = newValue
        }
    }
}

extension Trays {
    private static func mutate(_ body: (inout [Tray]) -> Bool) {
        var trays = all
        if body(&trays) { all = trays }
    }

    static func addSite(title: String, url: String, tray name: String?) {
        mutate { trays in
            guard !trays.isEmpty, !url.isEmpty else { return false }
            let index = name.flatMap { wanted in trays.firstIndex { $0.name == wanted } } ?? 0
            guard !trays[index].sites.contains(where: { $0.url == url }) else { return false }
            trays[index].sites.append(Site(title: title.isEmpty ? url : title, url: url))
            return true
        }
    }

    static func removeSite(url: String, tray name: String?) {
        mutate { trays in
            var changed = false
            for index in trays.indices where name == nil || trays[index].name == name {
                let before = trays[index].sites.count
                trays[index].sites.removeAll { $0.url == url }
                if trays[index].sites.count != before { changed = true }
            }
            return changed
        }
    }

    static func moveSite(url: String, tray name: String, to position: Int) {
        mutate { trays in
            guard let trayIndex = trays.firstIndex(where: { $0.name == name }),
                  let current = trays[trayIndex].sites.firstIndex(where: { $0.url == url }) else { return false }
            let clamped = max(0, min(position, trays[trayIndex].sites.count - 1))
            guard clamped != current else { return false }
            let site = trays[trayIndex].sites.remove(at: current)
            trays[trayIndex].sites.insert(site, at: clamped)
            return true
        }
    }

    static func renameSite(url: String, tray name: String, title: String) {
        mutate { trays in
            guard let trayIndex = trays.firstIndex(where: { $0.name == name }),
                  let siteIndex = trays[trayIndex].sites.firstIndex(where: { $0.url == url }),
                  !title.isEmpty else { return false }
            trays[trayIndex].sites[siteIndex].title = title
            return true
        }
    }

    static func addTray(name: String) {
        mutate { trays in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trays.contains(where: { $0.name == trimmed }) else { return false }
            trays.append(Tray(name: trimmed, sites: []))
            return true
        }
    }

    static func removeTray(name: String) {
        mutate { trays in
            guard trays.count > 1, let index = trays.firstIndex(where: { $0.name == name }) else { return false }
            trays.remove(at: index)
            return true
        }
    }

    static func renameTray(from: String, to: String) {
        mutate { trays in
            let trimmed = to.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let index = trays.firstIndex(where: { $0.name == from }),
                  !trays.contains(where: { $0.name == trimmed }) else { return false }
            trays[index].name = trimmed
            return true
        }
    }

    static func contains(url: String) -> Bool {
        all.contains { tray in tray.sites.contains { $0.url == url } }
    }
}
