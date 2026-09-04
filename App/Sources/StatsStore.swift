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
