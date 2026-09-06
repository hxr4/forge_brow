import AppKit

final class SidebarRowView: NSView {

    var onActivate: (() -> Void)?
    var onClose: (() -> Void)?
    var onMute: (() -> Void)?

    private let iconView = NSImageView()
    private let monogram = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let muteButton = NSButton()
    private let accent = NSView()
    private var tracking: NSTrackingArea?
    private var hovering = false
    private var active = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8

        accent.wantsLayer = true
        accent.layer?.cornerRadius = 1
        accent.isHidden = true
        addSubview(accent)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        monogram.font = .systemFont(ofSize: 11, weight: .semibold)
        monogram.textColor = Theme.muted
        monogram.alignment = .center
        addSubview(monogram)

        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textColor = Theme.bone
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 10)
        subtitleLabel.textColor = Theme.muted
        subtitleLabel.lineBreakMode = .byTruncatingTail
        addSubview(subtitleLabel)

        configure(muteButton, symbol: "speaker.slash.fill", action: #selector(handleMute))
        configure(closeButton, symbol: "xmark", action: #selector(handleClose))
    }

    required init?(coder: NSCoder) { fatalError() }

    private func configure(_ button: NSButton, symbol: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.isBordered = false
        button.contentTintColor = Theme.muted
        button.target = self
        button.action = action
        button.alphaValue = 0
        addSubview(button)
    }

    @objc private func handleClose() { onClose?() }
    @objc private func handleMute() { onMute?() }
    override func mouseDown(with event: NSEvent) { onActivate?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; restyle() }
    override func mouseExited(with event: NSEvent) { hovering = false; restyle() }

    private func restyle() {
        layer?.backgroundColor = (active ? Theme.panelHi : (hovering ? Theme.panel : .clear)).cgColor
        titleLabel.textColor = active ? Theme.cream : Theme.bone
        let show: CGFloat = (hovering || active) ? 1 : 0
        closeButton.animator().alphaValue = closeButton.isHidden ? 0 : show
        muteButton.animator().alphaValue = muteButton.isHidden ? 0 : show
    }

    func apply(title: String,
               subtitle: String,
               icon: NSImage?,
               active isActive: Bool,
               muted: Bool,
               accentColor: NSColor?,
               closable: Bool) {
        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle
        subtitleLabel.isHidden = subtitle.isEmpty
        toolTip = subtitle.isEmpty ? title : title + "\n" + subtitle

        iconView.image = icon
        iconView.isHidden = icon == nil
        monogram.isHidden = icon != nil
        monogram.stringValue = (title.first.map(String.init) ?? "?").uppercased()

        closeButton.isHidden = !closable
        muteButton.isHidden = !closable
        muteButton.contentTintColor = muted ? Theme.warn : Theme.muted

        accent.isHidden = accentColor == nil
        accent.layer?.backgroundColor = (accentColor ?? .clear).cgColor

        active = isActive
        restyle()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let height = bounds.height
        accent.frame = NSRect(x: 3, y: 6, width: 2, height: max(0, height - 12))
        let iconRect = NSRect(x: 12, y: (height - 16) / 2, width: 16, height: 16)
        iconView.frame = iconRect
        monogram.frame = iconRect

        var trailing = bounds.width - 6
        if !closeButton.isHidden {
            closeButton.frame = NSRect(x: trailing - 18, y: (height - 16) / 2, width: 16, height: 16)
            trailing -= 22
        }
        if !muteButton.isHidden {
            muteButton.frame = NSRect(x: trailing - 18, y: (height - 16) / 2, width: 16, height: 16)
            trailing -= 22
        }

        let textX: CGFloat = 36
        let width = max(20, trailing - textX)
        if subtitleLabel.isHidden {
            titleLabel.frame = NSRect(x: textX, y: (height - 15) / 2, width: width, height: 15)
        } else {
            titleLabel.frame = NSRect(x: textX, y: height / 2, width: width, height: 14)
            subtitleLabel.frame = NSRect(x: textX, y: height / 2 - 14, width: width, height: 12)
        }
    }
}

final class SidebarListView: NSView {
    override var isFlipped: Bool { true }

    private var rows: [SidebarRowView] = []
    private var headers: [NSTextField] = []
    private var layoutPlan: [(isHeader: Bool, index: Int)] = []

    static let rowHeight: CGFloat = 34
    static let headerHeight: CGFloat = 24

    var contentHeight: CGFloat {
        layoutPlan.reduce(6) { $0 + ($1.isHeader ? Self.headerHeight : Self.rowHeight) } + 8
    }

    func row(at index: Int) -> SidebarRowView {
        while rows.count <= index {
            let row = SidebarRowView()
            addSubview(row)
            rows.append(row)
        }
        return rows[index]
    }

    func header(at index: Int) -> NSTextField {
        while headers.count <= index {
            let label = NSTextField(labelWithString: "")
            label.font = .systemFont(ofSize: 9.5, weight: .heavy)
            label.textColor = Theme.mossDeep
            addSubview(label)
            headers.append(label)
        }
        return headers[index]
    }

    func finish(plan: [(isHeader: Bool, index: Int)], rowCount: Int, headerCount: Int) {
        layoutPlan = plan
        for index in rowCount..<rows.count { rows[index].isHidden = true }
        for index in headerCount..<headers.count { headers[index].isHidden = true }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        var y: CGFloat = 6
        for entry in layoutPlan {
            if entry.isHeader {
                headers[entry.index].frame = NSRect(x: 14, y: y + 8, width: bounds.width - 24, height: 12)
                y += Self.headerHeight
            } else {
                rows[entry.index].frame = NSRect(x: 6, y: y, width: bounds.width - 12, height: Self.rowHeight - 3)
                y += Self.rowHeight
            }
        }
    }
}

final class SidebarView: NSView {

    enum Section: String, CaseIterable {
        case tabs, tools, bookmarks, history, downloads

        var title: String {
            switch self {
            case .tabs: return "Tabs"
            case .tools: return "Tools"
            case .bookmarks: return "Bookmarks"
            case .history: return "History"
            case .downloads: return "Downloads"
            }
        }

        var symbol: String {
            switch self {
            case .tabs: return "square.on.square"
            case .tools: return "square.grid.2x2"
            case .bookmarks: return "bookmark"
            case .history: return "clock"
            case .downloads: return "arrow.down.circle"
            }
        }
    }

    static let railWidth: CGFloat = 46
    static let panelWidth: CGFloat = 268

    var onNavigate: ((String) -> Void)?
    var onSelectTab: ((UUID) -> Void)?
    var onCloseTab: ((UUID) -> Void)?
    var onMuteTab: ((UUID) -> Void)?
    var onHome: (() -> Void)?
    var onSettings: (() -> Void)?
    var onNewTab: (() -> Void)?
    var onLayoutChange: (() -> Void)?

    private(set) var isOpen = false
    private(set) var section: Section = .tabs

    private let rail = NSView()
    private let panel = NSView()
    private let divider = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let searchField = NSTextField()
    private let scroll = NSScrollView()
    private let list = SidebarListView()
    private var railButtons: [String: NSButton] = [:]

    private var tabs: [Tab] = []
    private var groups: [TabGroup] = []
    private var selectedIndex = 0
    private var filter = ""

    var preferredWidth: CGFloat { Self.railWidth + (isOpen ? Self.panelWidth : 0) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        rail.wantsLayer = true
        rail.layer?.backgroundColor = Theme.ink.cgColor
        addSubview(rail)

        panel.wantsLayer = true
        panel.layer?.masksToBounds = true
        panel.layer?.backgroundColor = NSColor(rgb: 0x070806).cgColor
        panel.isHidden = true
        addSubview(panel)

        divider.wantsLayer = true
        divider.layer?.backgroundColor = Theme.line.cgColor
        addSubview(divider)

        titleLabel.font = .systemFont(ofSize: 10, weight: .heavy)
        titleLabel.textColor = Theme.acid
        panel.addSubview(titleLabel)

        searchField.isBezeled = false
        searchField.drawsBackground = true
        searchField.backgroundColor = Theme.panel
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: 11.5)
        searchField.textColor = Theme.cream
        searchField.wantsLayer = true
        searchField.layer?.cornerRadius = 7
        searchField.placeholderAttributedString = NSAttributedString(
            string: "Filter",
            attributes: [.foregroundColor: Theme.muted, .font: NSFont.systemFont(ofSize: 11.5)])
        searchField.target = self
        searchField.action = #selector(handleFilter)
        panel.addSubview(searchField)

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        scroll.documentView = list
        panel.addSubview(scroll)

        buildRail()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func railButton(symbol: String, tooltip: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.isBordered = false
        button.contentTintColor = Theme.muted
        button.target = self
        button.action = action
        button.toolTip = tooltip
        button.wantsLayer = true
        button.layer?.cornerRadius = 9
        rail.addSubview(button)
        return button
    }

    private func buildRail() {
        railButtons["home"] = railButton(symbol: "house", tooltip: "Home", action: #selector(handleHome))
        for item in Section.allCases {
            let button = railButton(symbol: item.symbol, tooltip: item.title, action: #selector(handleSection(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(item.rawValue)
            railButtons[item.rawValue] = button
        }
        railButtons["settings"] = railButton(symbol: "gearshape", tooltip: "Settings",
                                             action: #selector(handleSettings))
    }

    @objc private func handleHome() { onHome?() }
    @objc private func handleSettings() { onSettings?() }
    @objc private func handleFilter() {
        filter = searchField.stringValue.lowercased()
        rebuild()
    }

    @objc private func handleSection(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let picked = Section(rawValue: raw) else { return }
        if isOpen && section == picked {
            isOpen = false
        } else {
            section = picked
            isOpen = true
        }
        panel.isHidden = !isOpen
        onLayoutChange?()
        rebuild()
    }

    func toggle() {
        isOpen.toggle()
        panel.isHidden = !isOpen
        rebuild()
        updateRailHighlight()
    }

    func update(tabs newTabs: [Tab], groups newGroups: [TabGroup], selectedIndex index: Int) {
        tabs = newTabs
        groups = newGroups
        selectedIndex = index
        if isOpen { rebuild() }
    }

    private func rebuild() {
        guard isOpen else { return }
        titleLabel.stringValue = section.title.uppercased()
        searchField.isHidden = section == .downloads

        var plan: [(isHeader: Bool, index: Int)] = []
        var rowIndex = 0
        var headerIndex = 0

        func addHeader(_ text: String) {
            let label = list.header(at: headerIndex)
            label.stringValue = text.uppercased()
            label.isHidden = false
            plan.append((true, headerIndex))
            headerIndex += 1
        }

        func addRow(title: String, subtitle: String, icon: NSImage?, active: Bool = false,
                    muted: Bool = false, accent: NSColor? = nil, closable: Bool = false,
                    activate: @escaping () -> Void,
                    close: (() -> Void)? = nil,
                    mute: (() -> Void)? = nil) {
            let row = list.row(at: rowIndex)
            row.isHidden = false
            row.onActivate = activate
            row.onClose = close
            row.onMute = mute
            row.apply(title: title, subtitle: subtitle, icon: icon, active: active,
                      muted: muted, accentColor: accent, closable: closable)
            plan.append((false, rowIndex))
            rowIndex += 1
        }

        func matches(_ text: String, _ other: String) -> Bool {
            filter.isEmpty || text.lowercased().contains(filter) || other.lowercased().contains(filter)
        }

        switch section {
        case .tabs:
            var ungrouped: [(Int, Tab)] = []
            var grouped: [UUID: [(Int, Tab)]] = [:]
            for (index, tab) in tabs.enumerated() {
                guard matches(tab.displayTitle, tab.url) else { continue }
                if let groupID = tab.groupID { grouped[groupID, default: []].append((index, tab)) }
                else { ungrouped.append((index, tab)) }
            }

            if !ungrouped.isEmpty {
                addHeader("Open tabs")
                for (index, tab) in ungrouped {
                    addRow(title: tab.displayTitle, subtitle: hostLabel(tab.url), icon: tab.favicon,
                           active: index == selectedIndex, muted: tab.isMuted, closable: true,
                           activate: { [weak self] in self?.onSelectTab?(tab.id) },
                           close: { [weak self] in self?.onCloseTab?(tab.id) },
                           mute: { [weak self] in self?.onMuteTab?(tab.id) })
                }
            }

            for group in groups {
                guard let members = grouped[group.id], !members.isEmpty else { continue }
                addHeader(group.name)
                for (index, tab) in members {
                    addRow(title: tab.displayTitle, subtitle: hostLabel(tab.url), icon: tab.favicon,
                           active: index == selectedIndex, muted: tab.isMuted, accent: group.color,
                           closable: true,
                           activate: { [weak self] in self?.onSelectTab?(tab.id) },
                           close: { [weak self] in self?.onCloseTab?(tab.id) },
                           mute: { [weak self] in self?.onMuteTab?(tab.id) })
                }
            }

        case .tools:
            var currentGroup = ""
            for tool in DevTools.all where matches(tool.name, tool.group) {
                if tool.group != currentGroup {
                    currentGroup = tool.group
                    addHeader(currentGroup)
                }
                addRow(title: tool.name, subtitle: "", icon: nil,
                       activate: { [weak self] in self?.onNavigate?(tool.url) })
            }

        case .bookmarks:
            for mark in BookmarkStore.shared.all where matches(mark.title, mark.url) {
                addRow(title: mark.title.isEmpty ? mark.url : mark.title,
                       subtitle: hostLabel(mark.url), icon: FaviconStore.shared.icon(for: mark.url),
                       activate: { [weak self] in self?.onNavigate?(mark.url) })
            }

        case .history:
            for entry in HistoryStore.shared.recent(120) where matches(entry.title, entry.url) {
                addRow(title: entry.title.isEmpty ? entry.url : entry.title,
                       subtitle: hostLabel(entry.url), icon: FaviconStore.shared.icon(for: entry.url),
                       activate: { [weak self] in self?.onNavigate?(entry.url) })
            }

        case .downloads:
            for item in FGDownloads.shared.snapshot() {
                let name = item["name"] as? String ?? "Download"
                let percent = (item["percent"] as? NSNumber)?.intValue ?? 0
                let complete = (item["complete"] as? NSNumber)?.boolValue ?? false
                addRow(title: name, subtitle: complete ? "Complete" : "\(percent)%", icon: nil,
                       activate: {})
            }
        }

        list.finish(plan: plan, rowCount: rowIndex, headerCount: headerIndex)
        needsLayout = true
        updateRailHighlight()
    }

    private func hostLabel(_ url: String) -> String {
        guard let host = URL(string: url)?.host else { return ForgeURL.display(for: url) }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    private func updateRailHighlight() {
        for (key, button) in railButtons {
            let selected = isOpen && key == section.rawValue
            button.contentTintColor = selected ? Theme.acid : Theme.muted
            button.layer?.backgroundColor = (selected ? Theme.panelHi : .clear).cgColor
        }
    }

    override func layout() {
        super.layout()
        rail.frame = NSRect(x: 0, y: 0, width: Self.railWidth, height: bounds.height)
        panel.frame = NSRect(x: Self.railWidth, y: 0,
                             width: max(0, bounds.width - Self.railWidth), height: bounds.height)
        divider.frame = NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height)

        let order = ["home"] + Section.allCases.map { $0.rawValue } + ["settings"]
        var y = bounds.height - 44
        for key in order {
            guard let button = railButtons[key] else { continue }
            if key == "settings" {
                button.frame = NSRect(x: 7, y: 12, width: 32, height: 32)
                continue
            }
            button.frame = NSRect(x: 7, y: y, width: 32, height: 32)
            y -= 38
        }

        titleLabel.frame = NSRect(x: 14, y: panel.bounds.height - 26, width: 180, height: 13)
        let searchHeight: CGFloat = searchField.isHidden ? 0 : 26
        if !searchField.isHidden {
            searchField.frame = NSRect(x: 10, y: panel.bounds.height - 62,
                                       width: panel.bounds.width - 20, height: 26)
        }
        scroll.frame = NSRect(x: 0, y: 0, width: panel.bounds.width,
                              height: max(0, panel.bounds.height - 38 - searchHeight - 6))
        list.frame = NSRect(x: 0, y: 0,
                            width: max(1, scroll.contentSize.width),
                            height: max(list.contentHeight, scroll.contentSize.height))
        list.needsLayout = true
        updateRailHighlight()
    }
}
