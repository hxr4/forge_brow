import Foundation

enum CustomRules {
    private static let key = "forge.blockedHosts"

    private(set) static var hosts: [String] = {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }()

    static func apply() {
        FGAdblock.shared.setBlockedHosts(hosts)
    }

    static func contains(_ host: String) -> Bool {
        hosts.contains(normalise(host))
    }

    @discardableResult
    static func toggle(_ host: String) -> Bool {
        let name = normalise(host)
        guard !name.isEmpty else { return false }
        if let index = hosts.firstIndex(of: name) {
            hosts.remove(at: index)
        } else {
            hosts.append(name)
            hosts.sort()
        }
        persist()
        return hosts.contains(name)
    }

    static func remove(_ host: String) {
        hosts.removeAll { $0 == normalise(host) }
        persist()
    }

    private static func persist() {
        UserDefaults.standard.set(hosts, forKey: key)
        apply()
    }

    private static func normalise(_ host: String) -> String {
        var name = host.lowercased().trimmingCharacters(in: .whitespaces)
        if name.hasPrefix("www.") { name = String(name.dropFirst(4)) }
        return name
    }
}
