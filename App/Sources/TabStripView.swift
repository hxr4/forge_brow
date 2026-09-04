import AppKit

final class TabStripView: NSView {

    var orientation: TabOrientation = .horizontal {
        didSet {
            guard orientation != oldValue else { return }
            layoutItems(animated: true)
        }
    }

    var onSelect: ((UUID) -> Void)?
    var onClose: ((UUID) -> Void)?
    var onNewTab: (() -> Void)?
    var onToggleGroup: ((UUID) -> Void)?

    private enum StripEntry {
        case group(UUID)
        case tab(UUID)

        var key: String {
            switch self {
            case .group(let id): return "g" + id.uuidString
            case .tab(let id): return "t" + id.uuidString
            }
        }
    }

    private var itemsByID: [UUID: TabItemView] = [:]
    private var headersByID: [UUID: TabGroupHeaderView] = [:]
    private var pendingEntrance: Set<UUID> = []
    private var entries: [StripEntry] = []
    private let newTabButton = NSButton()
    private let edgeView = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.void.cgColor

        newTabButton.title = "+"
        newTabButton.font = .systemFont(ofSize: 15, weight: .light)
        newTabButton.isBordered = false
        newTabButton.contentTintColor = Theme.muted
        newTabButton.target = self
        newTabButton.action = #selector(handleNewTab)
        newTabButton.wantsLayer = true
        newTabButton.layer?.cornerRadius = Theme.Metrics.tabRadius
        addSubview(newTabButton)

        edgeView.wantsLayer = true
        edgeView.layer?.backgroundColor = Theme.line.cgColor
        addSubview(edgeView)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func handleNewTab() { onNewTab?() }

    func update(with tabs: [Tab], groups: [TabGroup], selectedIndex: Int) {
        var incoming: [StripEntry] = []
        var visibleTabIDs = Set<UUID>()
        var emittedGroups = Set<UUID>()
        var counts: [UUID: Int] = [:]

        for tab in tabs {
            guard let groupID = tab.groupID else { continue }
            counts[groupID, default: 0] += 1
        }

        for tab in tabs {
            if let groupID = tab.groupID, let group = groups.first(where: { $0.id == groupID }) {
                if emittedGroups.insert(groupID).inserted {
                    incoming.append(.group(groupID))
                }
                if group.isCollapsed { continue }
            }
            incoming.append(.tab(tab.id))
            visibleTabIDs.insert(tab.id)
        }

        var structureChanged = entries.map(\.key) != incoming.map(\.key)

        for (id, view) in itemsByID where !visibleTabIDs.contains(id) {
            structureChanged = true
            Theme.animate(0.16) { view.animator().alphaValue = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { view.removeFromSuperview() }
            itemsByID.removeValue(forKey: id)
        }

        for (id, view) in headersByID where !emittedGroups.contains(id) {
            structureChanged = true
            view.removeFromSuperview()
            headersByID.removeValue(forKey: id)
        }

        for group in groups where emittedGroups.contains(group.id) {
            let header: TabGroupHeaderView
            if let existing = headersByID[group.id] {
                header = existing
            } else {
                structureChanged = true
                header = TabGroupHeaderView(groupID: group.id)
                header.onToggle = { [weak self] in self?.onToggleGroup?(group.id) }
                addSubview(header)
                headersByID[group.id] = header
            }
            header.apply(group, count: counts[group.id] ?? 0)
        }

        for (index, tab) in tabs.enumerated() where visibleTabIDs.contains(tab.id) {
            let view: TabItemView
            if let existing = itemsByID[tab.id] {
                view = existing
            } else {
                structureChanged = true
                view = TabItemView(tabID: tab.id)
                view.alphaValue = 0
                pendingEntrance.insert(tab.id)
                view.onSelect = { [weak self] in self?.onSelect?(tab.id) }
                view.onClose = { [weak self] in self?.onClose?(tab.id) }
                addSubview(view)
                itemsByID[tab.id] = view
            }
            let group = tab.groupID.flatMap { id in groups.first { $0.id == id } }
            view.apply(
                title: tab.displayTitle,
                favicon: tab.favicon,
                active: index == selectedIndex,
                bypass: tab.hasActiveBypass,
                busy: tab.isLoading,
                groupColor: group?.color
            )
        }

        entries = incoming
        if structureChanged { layoutItems(animated: true) }
    }

    override func layout() {
        super.layout()
        layoutItems(animated: false)
    }

    private var isLayingOut = false

    private func layoutItems(animated: Bool) {
        guard !isLayingOut else { return }
        isLayingOut = true
        defer { isLayingOut = false }

        let inset = Theme.Metrics.stripInset
        let height = Theme.Metrics.tabHeight
        let gap: CGFloat = 5

        var frames: [String: NSRect] = [:]
        var newTabFrame = NSRect.zero

        if orientation == .horizontal {
            var headerWidth: CGFloat = 0
            var tabCount: CGFloat = 0
            for entry in entries {
                switch entry {
                case .group(let id): headerWidth += (headersByID[id]?.preferredWidth ?? 70) + gap
                case .tab: tabCount += 1
                }
            }
            let available = bounds.width - inset * 2 - 34 - headerWidth
            let width = min(190, max(72, (available - gap * max(tabCount - 1, 0)) / max(tabCount, 1)))
            var x = inset
            let y = (bounds.height - height) / 2
            for entry in entries {
                switch entry {
                case .group(let id):
                    let itemWidth = headersByID[id]?.preferredWidth ?? 70
                    frames[entry.key] = NSRect(x: x, y: y, width: itemWidth, height: height)
                    x += itemWidth + gap
                case .tab:
                    frames[entry.key] = NSRect(x: x, y: y, width: width, height: height)
                    x += width + gap
                }
            }
            newTabFrame = NSRect(x: min(x, bounds.width - inset - 28), y: y, width: 28, height: height)
        } else {
            let width = bounds.width - inset * 2
            var y = bounds.height - inset - height
            for entry in entries {
                switch entry {
                case .group:
                    frames[entry.key] = NSRect(x: inset, y: y, width: width, height: height)
                case .tab:
                    frames[entry.key] = NSRect(x: inset + 10, y: y, width: width - 10, height: height)
                }
                y -= height + gap
            }
            newTabFrame = NSRect(x: inset, y: y, width: width, height: height)
        }

        layer?.backgroundColor = (orientation == .vertical ? Theme.ink : Theme.void).cgColor
        edgeView.isHidden = orientation == .horizontal
        edgeView.frame = NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height)

        for id in pendingEntrance {
            guard let view = itemsByID[id], let frame = frames["t" + id.uuidString] else { continue }
            view.frame = frame
            view.alphaValue = 0
        }

        let entering = pendingEntrance
        pendingEntrance.removeAll()

        let apply = {
            for entry in self.entries {
                guard let frame = frames[entry.key] else { continue }
                switch entry {
                case .group(let id):
                    guard let header = self.headersByID[id] else { continue }
                    if animated { header.animator().frame = frame } else { header.frame = frame }
                case .tab(let id):
                    guard let view = self.itemsByID[id] else { continue }
                    if entering.contains(id) {
                        view.animator().alphaValue = 1
                    } else if animated {
                        view.animator().frame = frame
                        view.animator().alphaValue = 1
                    } else {
                        view.frame = frame
                        view.alphaValue = 1
                    }
                }
            }
            if animated {
                self.newTabButton.animator().frame = newTabFrame
            } else {
                self.newTabButton.frame = newTabFrame
            }
        }

        if animated { Theme.animate(0.24, apply) } else { apply() }
    }
}
