import AppKit

final class ClippingView: NSView {
    override var isFlipped: Bool { false }
}

final class TabStripView: NSView {

    var orientation: TabOrientation = .horizontal {
        didSet {
            guard orientation != oldValue else { return }
            scrollOffset = 0
            layoutItems(animated: true)
        }
    }

    var onSelect: ((UUID) -> Void)?
    var onClose: ((UUID) -> Void)?
    var onNewTab: (() -> Void)?
    var onToggleGroup: ((UUID) -> Void)?
    var menuProvider: ((UUID) -> NSMenu?)?
    var overflowMenuProvider: (() -> NSMenu?)?

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
    private var selectedTabID: UUID?

    private let clip = ClippingView()
    private let newTabButton = NSButton()
    private let overflowButton = NSButton()
    private let edgeView = NSView()

    private var scrollOffset: CGFloat = 0
    private var contentLength: CGFloat = 0
    private var viewportLength: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.void.cgColor

        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        addSubview(clip)

        newTabButton.title = "+"
        newTabButton.font = .systemFont(ofSize: 15, weight: .light)
        newTabButton.isBordered = false
        newTabButton.contentTintColor = Theme.muted
        newTabButton.target = self
        newTabButton.action = #selector(handleNewTab)
        newTabButton.wantsLayer = true
        newTabButton.layer?.cornerRadius = Theme.Metrics.tabRadius
        newTabButton.toolTip = "New Tab"
        addSubview(newTabButton)

        overflowButton.title = "⌄"
        overflowButton.font = .systemFont(ofSize: 13, weight: .medium)
        overflowButton.isBordered = false
        overflowButton.contentTintColor = Theme.bone
        overflowButton.target = self
        overflowButton.action = #selector(handleOverflow)
        overflowButton.wantsLayer = true
        overflowButton.layer?.cornerRadius = Theme.Metrics.tabRadius
        overflowButton.isHidden = true
        overflowButton.toolTip = "All tabs"
        addSubview(overflowButton)

        edgeView.wantsLayer = true
        edgeView.layer?.backgroundColor = Theme.line.cgColor
        addSubview(edgeView)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func handleNewTab() { onNewTab?() }

    @objc private func handleOverflow() {
        guard let menu = overflowMenuProvider?() else { return }
        let origin = NSPoint(x: overflowButton.frame.minX,
                             y: orientation == .horizontal ? overflowButton.frame.minY : overflowButton.frame.maxY)
        menu.popUp(positioning: nil, at: origin, in: self)
    }

    override func scrollWheel(with event: NSEvent) {
        guard contentLength > viewportLength else {
            super.scrollWheel(with: event)
            return
        }
        let delta = orientation == .horizontal
            ? (abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY)
            : event.scrollingDeltaY
        scrollOffset = clampedOffset(scrollOffset - delta)
        layoutItems(animated: false)
    }

    private func clampedOffset(_ value: CGFloat) -> CGFloat {
        max(0, min(value, max(0, contentLength - viewportLength)))
    }

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
        let previousSelection = selectedTabID
        selectedTabID = tabs.indices.contains(selectedIndex) ? tabs[selectedIndex].id : nil

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
                clip.addSubview(header)
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
                view.menuProvider = { [weak self] in self?.menuProvider?(tab.id) }
                clip.addSubview(view)
                itemsByID[tab.id] = view
            }
            let group = tab.groupID.flatMap { id in groups.first { $0.id == id } }
            view.apply(
                title: tab.displayTitle,
                favicon: tab.favicon,
                active: index == selectedIndex,
                bypass: tab.hasActiveBypass,
                busy: tab.isLoading,
                muted: tab.isMuted,
                groupColor: group?.color
            )
        }

        entries = incoming
        if structureChanged || previousSelection != selectedTabID {
            layoutItems(animated: structureChanged)
            revealSelected()
        }
    }

    override func layout() {
        super.layout()
        layoutItems(animated: false)
    }

    private var isLayingOut = false

    private func revealSelected() {
        guard let id = selectedTabID, let frame = lastFrames["t" + id.uuidString] else { return }
        guard contentLength > viewportLength else { return }

        if orientation == .horizontal {
            let leading = frame.minX + scrollOffset
            let trailing = frame.maxX + scrollOffset
            if leading < scrollOffset {
                scrollOffset = clampedOffset(leading - 8)
            } else if trailing > scrollOffset + viewportLength {
                scrollOffset = clampedOffset(trailing - viewportLength + 8)
            } else {
                return
            }
        } else {
            let top = contentLength - (frame.maxY + scrollOffset)
            if top < scrollOffset {
                scrollOffset = clampedOffset(top - 8)
            } else if top + frame.height > scrollOffset + viewportLength {
                scrollOffset = clampedOffset(top + frame.height - viewportLength + 8)
            } else {
                return
            }
        }
        layoutItems(animated: false)
    }

    private var lastFrames: [String: NSRect] = [:]

    private func layoutItems(animated: Bool) {
        guard !isLayingOut else { return }
        isLayingOut = true
        defer { isLayingOut = false }

        let inset = Theme.Metrics.stripInset
        let height = Theme.Metrics.tabHeight
        let gap: CGFloat = 5
        let buttonSize: CGFloat = 28

        var frames: [String: NSRect] = [:]

        if orientation == .horizontal {
            var needed: CGFloat = 0
            var tabCount: CGFloat = 0
            for entry in entries {
                switch entry {
                case .group(let id): needed += (headersByID[id]?.preferredWidth ?? 70) + gap
                case .tab: tabCount += 1
                }
            }

            let reserved = inset + buttonSize + gap + buttonSize + inset
            viewportLength = max(60, bounds.width - reserved)
            let idealTabWidth: CGFloat = 190
            let minimumTabWidth: CGFloat = 108
            let roomForTabs = viewportLength - needed - gap * max(tabCount - 1, 0)
            let width = tabCount > 0
                ? min(idealTabWidth, max(minimumTabWidth, roomForTabs / tabCount))
                : idealTabWidth
            contentLength = needed + width * tabCount + gap * max(tabCount - 1, 0)
            scrollOffset = clampedOffset(scrollOffset)

            clip.frame = NSRect(x: inset, y: 0, width: viewportLength, height: bounds.height)

            var x: CGFloat = -scrollOffset
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

            let overflowing = contentLength > viewportLength + 0.5
            overflowButton.isHidden = !overflowing
            overflowButton.frame = NSRect(x: bounds.width - inset - buttonSize * 2 - gap,
                                          y: y, width: buttonSize, height: height)
            newTabButton.frame = NSRect(x: bounds.width - inset - buttonSize,
                                        y: y, width: buttonSize, height: height)
        } else {
            let width = bounds.width - inset * 2
            let reserved = inset + height + inset
            viewportLength = max(60, bounds.height - reserved)
            contentLength = CGFloat(entries.count) * (height + gap)
            scrollOffset = clampedOffset(scrollOffset)

            clip.frame = NSRect(x: 0, y: bounds.height - inset - viewportLength,
                                width: bounds.width, height: viewportLength)

            var y = viewportLength - height + scrollOffset
            for entry in entries {
                switch entry {
                case .group:
                    frames[entry.key] = NSRect(x: inset, y: y, width: width, height: height)
                case .tab:
                    frames[entry.key] = NSRect(x: inset + 10, y: y, width: width - 10, height: height)
                }
                y -= height + gap
            }

            overflowButton.isHidden = contentLength <= viewportLength + 0.5
            overflowButton.frame = NSRect(x: bounds.width - inset - buttonSize, y: inset,
                                          width: buttonSize, height: height)
            newTabButton.frame = NSRect(x: inset, y: inset,
                                        width: overflowButton.isHidden ? width : width - buttonSize - gap,
                                        height: height)
        }

        lastFrames = frames
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
        }

        if animated { Theme.animate(0.24, apply) } else { apply() }
    }
}
