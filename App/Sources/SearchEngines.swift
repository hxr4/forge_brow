import Foundation

struct SearchEngine: Equatable {
    let id: String
    let name: String
    let queryTemplate: String
    let suggestTemplate: String?

    func url(for query: String) -> String {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return queryTemplate.replacingOccurrences(of: "{query}", with: encoded)
    }
}

enum SearchEngines {
    static let duckDuckGo = SearchEngine(
        id: "ddg",
        name: "DuckDuckGo",
        queryTemplate: "https://duckduckgo.com/?q={query}",
        suggestTemplate: "https://duckduckgo.com/ac/?q={query}&type=list"
    )

    static let brave = SearchEngine(
        id: "brave",
        name: "Brave Search",
        queryTemplate: "https://search.brave.com/search?q={query}",
        suggestTemplate: "https://search.brave.com/api/suggest?q={query}"
    )

    static let all: [SearchEngine] = [duckDuckGo, brave]

    private static let defaultsKey = "forge.searchEngine"

    static var current: SearchEngine {
        get {
            let identifier = UserDefaults.standard.string(forKey: defaultsKey) ?? duckDuckGo.id
            return all.first { $0.id == identifier } ?? duckDuckGo
        }
        set {
            UserDefaults.standard.set(newValue.id, forKey: defaultsKey)
        }
    }

    static func engine(withID identifier: String) -> SearchEngine? {
        all.first { $0.id == identifier }
    }
}

enum ForgeURL {
    static let internalPages: [(alias: String, path: String, label: String)] = [
        ("forge://home",      "forge://home/index.html",     ""),
        ("forge://settings",  "forge://home/settings.html",  "forge://settings"),
        ("forge://history",   "forge://home/history.html",   "forge://history"),
        ("forge://bookmarks", "forge://home/bookmarks.html", "forge://bookmarks"),
        ("forge://downloads", "forge://home/downloads.html", "forge://downloads"),
        ("forge://help",      "forge://home/help.html",      "forge://help"),
        ("forge://tools",     "forge://home/tools.html",     "forge://tools")
    ]

    static func canonical(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "/$", with: "", options: .regularExpression)
        for page in internalPages where page.alias == trimmed { return page.path }
        return nil
    }

    static func display(for url: String) -> String {
        let normalised = url == "forge://home/" ? "forge://home/index.html" : url
        for page in internalPages where page.path == normalised { return page.label }
        if normalised.hasPrefix("forge://home/tools/") {
            let name = normalised
                .replacingOccurrences(of: "forge://home/tools/", with: "")
                .replacingOccurrences(of: ".html", with: "")
            return "forge://tools/" + name
        }
        return url
    }

    static func isInternal(_ url: String) -> Bool { url.hasPrefix("forge://") }
}

enum AddressResolver {
    static func resolve(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "about:blank" }

        if let canonical = ForgeURL.canonical(trimmed) { return canonical }
        if trimmed.hasPrefix("forge://") || trimmed.hasPrefix("about:") || trimmed.hasPrefix("devtools://") {
            return trimmed
        }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || trimmed.hasPrefix("file://") {
            return trimmed
        }
        if trimmed.hasPrefix("localhost") || trimmed.hasPrefix("127.0.0.1") {
            return "http://" + trimmed
        }
        if !trimmed.contains(" "), looksLikeHost(trimmed) {
            return "https://" + trimmed
        }
        return SearchEngines.current.url(for: trimmed)
    }

    private static func looksLikeHost(_ value: String) -> Bool {
        let host = value.split(separator: "/").first.map(String.init) ?? value
        guard host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".") else { return false }
        let labels = host.split(separator: ".")
        guard labels.count >= 2, let last = labels.last, last.count >= 2 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.:")
        return host.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
