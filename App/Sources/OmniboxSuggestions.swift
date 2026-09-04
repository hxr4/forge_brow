import AppKit

struct Suggestion: Equatable {
    enum Kind {
        case navigate
        case search
        case history
        case bookmark
    }

    let kind: Kind
    let title: String
    let subtitle: String
    let target: String

    var glyph: String {
        switch kind {
        case .navigate: return "→"
        case .search: return "⌕"
        case .history: return "↺"
        case .bookmark: return "★"
        }
    }
}

enum SuggestionSettings {
    private static let key = "forge.remoteSuggestions"

    static var remoteEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: key) == nil { return true }
            return UserDefaults.standard.bool(forKey: key)
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

final class SuggestionEngine {
    static let shared = SuggestionEngine()

    private var inFlight: URLSessionDataTask?
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration)
    }

    func local(for query: String, limit: Int = 5) -> [Suggestion] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return [] }

        var results: [Suggestion] = []
        var seen = Set<String>()

        for bookmark in BookmarkStore.shared.all
        where bookmark.title.lowercased().contains(needle) || bookmark.url.lowercased().contains(needle) {
            guard seen.insert(bookmark.url).inserted else { continue }
            results.append(Suggestion(kind: .bookmark,
                                      title: bookmark.title.isEmpty ? bookmark.url : bookmark.title,
                                      subtitle: bookmark.url,
                                      target: bookmark.url))
            if results.count >= limit { return results }
        }

        for entry in HistoryStore.shared.search(query, limit: limit * 4) {
            guard seen.insert(entry.url).inserted else { continue }
            results.append(Suggestion(kind: .history,
                                      title: entry.title.isEmpty ? entry.url : entry.title,
                                      subtitle: entry.url,
                                      target: entry.url))
            if results.count >= limit { return results }
        }

        return results
    }

    func remote(for query: String, completion: @escaping ([String]) -> Void) {
        inFlight?.cancel()
        inFlight = nil

        guard SuggestionSettings.remoteEnabled,
              !query.trimmingCharacters(in: .whitespaces).isEmpty,
              let template = SearchEngines.current.suggestTemplate else {
            completion([])
            return
        }

        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: template.replacingOccurrences(of: "{query}", with: encoded)) else {
            completion([])
            return
        }

        let task = session.dataTask(with: url) { data, _, _ in
            guard let data,
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [Any],
                  parsed.count >= 2,
                  let phrases = parsed[1] as? [String] else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            DispatchQueue.main.async { completion(Array(phrases.prefix(6))) }
        }
        inFlight = task
        task.resume()
    }

    func cancel() {
        inFlight?.cancel()
        inFlight = nil
    }
}

final class SuggestionRowView: NSView {
    let index: Int
    var onPick: (() -> Void)?

    private let glyphLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private var measuredTitleWidth: CGFloat = 0

    init(index: Int) {
        self.index = index
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7

        glyphLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        glyphLabel.textColor = Theme.mossDeep
        glyphLabel.alignment = .center

        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = Theme.cream
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = Theme.muted
        subtitleLabel.lineBreakMode = .byTruncatingMiddle

        for view in [glyphLabel, titleLabel, subtitleLabel] { addSubview(view) }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let height = bounds.height
        glyphLabel.frame = NSRect(x: 10, y: (height - 16) / 2, width: 18, height: 16)
        let textX: CGFloat = 36
        let available = bounds.width - textX - 14
        let titleWidth = min(available * 0.62, measuredTitleWidth + 4)
        titleLabel.frame = NSRect(x: textX, y: (height - 17) / 2, width: max(40, titleWidth), height: 17)
        let subtitleX = titleLabel.frame.maxX + 10
        subtitleLabel.frame = NSRect(x: subtitleX, y: (height - 15) / 2,
                                     width: max(0, bounds.width - subtitleX - 14), height: 15)
    }

    func apply(_ suggestion: Suggestion, highlighted: Bool) {
        glyphLabel.stringValue = suggestion.glyph
        titleLabel.stringValue = suggestion.title
        measuredTitleWidth = titleLabel
            .sizeThatFits(NSSize(width: CGFloat.greatestFiniteMagnitude, height: 17))
            .width
        subtitleLabel.stringValue = suggestion.subtitle
        layer?.backgroundColor = highlighted ? Theme.panelHi.cgColor : NSColor.clear.cgColor
        titleLabel.textColor = highlighted ? Theme.cream : Theme.bone
        glyphLabel.textColor = highlighted ? Theme.acid : Theme.mossDeep
        needsLayout = true
    }

    override func mouseDown(with event: NSEvent) { onPick?() }
}

final class OmniboxSuggestionsView: NSView {

    private static let rowHeight: CGFloat = 34
    private static let padding: CGFloat = 6

    private var rows: [SuggestionRowView] = []
    private(set) var suggestions: [Suggestion] = []
    private(set) var highlighted: Int = 0

    var onPick: ((Suggestion) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.ink.cgColor
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = Theme.line.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.55
        layer?.shadowRadius = 22
        layer?.shadowOffset = NSSize(width: 0, height: -6)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    var isPresenting: Bool { !isHidden && !suggestions.isEmpty }

    var selected: Suggestion? {
        guard highlighted >= 0, highlighted < suggestions.count else { return nil }
        return suggestions[highlighted]
    }

    func present(_ items: [Suggestion], anchor: NSRect) {
        suggestions = items
        if highlighted >= items.count { highlighted = 0 }

        guard !items.isEmpty else {
            dismiss()
            return
        }

        while rows.count < items.count {
            let row = SuggestionRowView(index: rows.count)
            let position = rows.count
            row.onPick = { [weak self] in
                guard let self, position < self.suggestions.count else { return }
                self.onPick?(self.suggestions[position])
            }
            addSubview(row)
            rows.append(row)
        }

        let height = CGFloat(items.count) * Self.rowHeight + Self.padding * 2
        frame = NSRect(x: anchor.minX, y: anchor.minY - height - 6, width: anchor.width, height: height)

        for (index, row) in rows.enumerated() {
            row.isHidden = index >= items.count
            guard index < items.count else { continue }
            row.frame = NSRect(x: Self.padding,
                               y: bounds.height - Self.padding - CGFloat(index + 1) * Self.rowHeight,
                               width: bounds.width - Self.padding * 2,
                               height: Self.rowHeight)
            row.apply(items[index], highlighted: index == highlighted)
        }

        if isHidden {
            alphaValue = 0
            isHidden = false
            Theme.animate(0.14) { self.animator().alphaValue = 1 }
        }
    }

    func move(by offset: Int) {
        guard !suggestions.isEmpty else { return }
        highlighted = (highlighted + offset + suggestions.count) % suggestions.count
        for (index, row) in rows.enumerated() where index < suggestions.count {
            row.apply(suggestions[index], highlighted: index == highlighted)
        }
    }

    func dismiss() {
        guard !isHidden else { return }
        Theme.animate(0.12) { self.animator().alphaValue = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            if self.alphaValue == 0 { self.isHidden = true }
        }
        suggestions = []
        highlighted = 0
    }
}
