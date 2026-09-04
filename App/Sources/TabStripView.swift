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

    private var itemsByID: [UUID: TabItemView] = [:]
    private var pendingEntrance: Set<UUID> = []
    private var order: [UUID] = []
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

    func update(with tabs: [Tab], selectedIndex: Int) {
        let incoming = tabs.map { $0.id }

        for (id, view) in itemsByID where !incoming.contains(id) {
            Theme.animate(0.16) {
                view.animator().alphaValue = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                view.removeFromSuperview()
            }
            itemsByID.removeValue(forKey: id)
        }

        for (index, tab) in tabs.enumerated() {
            let view: TabItemView
            if let existing = itemsByID[tab.id] {
                view = existing
            } else {
                view = TabItemView(tabID: tab.id)
                view.alphaValue = 0
                pendingEntrance.insert(tab.id)
                view.onSelect = { [weak self] in self?.onSelect?(tab.id) }
                view.onClose = { [weak self] in self?.onClose?(tab.id) }
                addSubview(view)
                itemsByID[tab.id] = view
            }
            view.apply(
                title: tab.displayTitle,
                favicon: tab.favicon,
                active: index == selectedIndex,
                bypass: tab.hasActiveBypass,
                busy: tab.isLoading
            )
        }

        order = incoming
        layoutItems(animated: true)
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

        var frames: [UUID: NSRect] = [:]
        var newTabFrame = NSRect.zero

        if orientation == .horizontal {
            let available = bounds.width - inset * 2 - 34
            let count = CGFloat(max(order.count, 1))
            let width = min(190, max(72, (available - gap * (count - 1)) / count))
            var x = inset
            let y = (bounds.height - height) / 2
            for id in order {
                frames[id] = NSRect(x: x, y: y, width: width, height: height)
                x += width + gap
            }
            newTabFrame = NSRect(x: min(x, bounds.width - inset - 28), y: y, width: 28, height: height)
        } else {
            let width = bounds.width - inset * 2
            var y = bounds.height - inset - height
            for id in order {
                frames[id] = NSRect(x: inset, y: y, width: width, height: height)
                y -= height + gap
            }
            newTabFrame = NSRect(x: inset, y: y, width: width, height: height)
        }

        self.layer?.backgroundColor = (self.orientation == .vertical ? Theme.ink : Theme.void).cgColor
        edgeView.isHidden = orientation == .horizontal
        edgeView.frame = NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height)

        for id in pendingEntrance {
            guard let view = itemsByID[id], let frame = frames[id] else { continue }
            view.frame = frame
            view.alphaValue = 0
        }

        let entering = pendingEntrance
        pendingEntrance.removeAll()

        let apply = {
            for id in self.order {
                guard let view = self.itemsByID[id], let frame = frames[id] else { continue }
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
            if animated {
                self.newTabButton.animator().frame = newTabFrame
            } else {
                self.newTabButton.frame = newTabFrame
            }
        }

        if animated { Theme.animate(0.24, apply) } else { apply() }
    }
}
