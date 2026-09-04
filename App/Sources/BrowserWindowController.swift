import AppKit

final class BrowserWindowController: NSWindowController, FGBrowserViewDelegate, NSTextFieldDelegate {

    private var tabs: [Tab] = []
    private var selectedIndex: Int = 0

    private let chrome = ChromeContainer()
    private let tabStrip = TabStripView()
    private let toolbarView = CallbackView()
    private let dividerView = NSView()
    private let contentContainer = NSView()

    private let addressBox = AddressFieldContainer()
    private let addressField = NSTextField()
    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private let reloadButton = NSButton()
    private let layoutButton = NSButton()
    private let paletteButton = NSButton()
    private let bypassPill = NSTextField(labelWithString: "")
    private let blockCounter = NSTextField(labelWithString: "")

    private let palette = CommandPaletteController()
    private let findBar = FindBar()
    private let suggestionsView = OmniboxSuggestionsView()
    private var suggestionDebounce: Timer?
    private var suggestionQuery = ""
    private var findVisible = false
    private var stateTimer: Timer?

    private static let orientationKey = "forge.tabOrientation"

    private var orientation: TabOrientation {
        get {
            let raw = UserDefaults.standard.string(forKey: Self.orientationKey) ?? TabOrientation.horizontal.rawValue
            return TabOrientation(rawValue: raw) ?? .horizontal
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.orientationKey)
            chrome.orientation = newValue
            tabStrip.orientation = newValue
            layoutButton.title = newValue == .horizontal ? "▤" : "▥"
        }
    }

    private var selectedTab: Tab? {
        guard selectedIndex >= 0, selectedIndex < tabs.count else { return nil }
        return tabs[selectedIndex]
    }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1360, height: 880),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Forge"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Theme.void
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()
        window.setFrameAutosaveName("ForgeMainWindow")
        self.init(window: window)
        buildInterface()
        configurePalette()
        startMonitors()
        newTab(url: "forge://home/")
    }

    private func buildInterface() {
        guard let root = window?.contentView else { return }
        root.wantsLayer = true
        root.layer?.backgroundColor = Theme.void.cgColor

        chrome.autoresizingMask = [.width, .height]
        chrome.frame = root.bounds
        root.addSubview(chrome)

        tabStrip.onSelect = { [weak self] id in self?.selectTab(id: id) }
        tabStrip.onClose = { [weak self] id in self?.closeTab(id: id) }
        tabStrip.onNewTab = { [weak self] in self?.handleNewTab() }

        toolbarView.wantsLayer = true
        toolbarView.layer?.backgroundColor = Theme.ink.cgColor
        toolbarView.onLayout = { [weak self] in self?.layoutToolbar() }

        dividerView.wantsLayer = true
        dividerView.layer?.backgroundColor = Theme.line.cgColor

        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = Theme.void.cgColor

        chrome.addSubview(contentContainer)
        chrome.addSubview(tabStrip)
        chrome.addSubview(toolbarView)
        chrome.addSubview(dividerView)

        chrome.tabStrip = tabStrip
        chrome.toolbar = toolbarView
        chrome.content = contentContainer
        chrome.divider = dividerView

        buildToolbar()
        buildFindBar()
        buildSuggestions()
        orientation = orientation
    }

    private func buildToolbar() {
        style(button: backButton, glyph: "‹", action: #selector(handleBack))
        style(button: forwardButton, glyph: "›", action: #selector(handleForward))
        style(button: reloadButton, glyph: "⟳", action: #selector(handleReload))
        style(button: layoutButton, glyph: "▤", action: #selector(handleToggleOrientation))
        style(button: paletteButton, glyph: "⌘K", action: #selector(handleTogglePalette))
        paletteButton.font = .systemFont(ofSize: 11, weight: .semibold)

        addressField.isBezeled = false
        addressField.drawsBackground = false
        addressField.focusRingType = .none
        addressField.font = .systemFont(ofSize: 13)
        addressField.textColor = Theme.cream
        addressField.delegate = self
        addressField.target = self
        addressField.action = #selector(handleAddressSubmit)
        addressField.placeholderAttributedString = NSAttributedString(
            string: "Search, or type a URL",
            attributes: [.foregroundColor: Theme.muted, .font: NSFont.systemFont(ofSize: 13)]
        )
        addressField.translatesAutoresizingMaskIntoConstraints = false
        addressBox.addSubview(addressField)
        NSLayoutConstraint.activate([
            addressField.leadingAnchor.constraint(equalTo: addressBox.leadingAnchor, constant: 13),
            addressField.trailingAnchor.constraint(equalTo: addressBox.trailingAnchor, constant: -13),
            addressField.centerYAnchor.constraint(equalTo: addressBox.centerYAnchor)
        ])

        bypassPill.font = .systemFont(ofSize: 10, weight: .heavy)
        bypassPill.textColor = Theme.void
        bypassPill.alignment = .center
        bypassPill.wantsLayer = true
        bypassPill.layer?.backgroundColor = Theme.warn.cgColor
        bypassPill.layer?.cornerRadius = 5
        bypassPill.layer?.shadowColor = Theme.warn.cgColor
        bypassPill.layer?.shadowOpacity = 0.5
        bypassPill.layer?.shadowRadius = 10
        bypassPill.layer?.shadowOffset = .zero
        bypassPill.isHidden = true

        blockCounter.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        blockCounter.textColor = Theme.moss

        for view in [backButton, forwardButton, reloadButton, addressBox, bypassPill, blockCounter, layoutButton, paletteButton] {
            toolbarView.addSubview(view)
        }
        layoutToolbar()
    }

    private func buildFindBar() {
        findBar.isHidden = true
        findBar.alphaValue = 0
        findBar.onQueryChange = { [weak self] query in
            guard let self else { return }
            if query.isEmpty {
                self.selectedTab?.browserView.stopFinding(true)
                self.findBar.setMatches(count: 0, active: 0)
            } else {
                self.selectedTab?.browserView.findText(query, forward: true, matchCase: false, findNext: false)
            }
        }
        findBar.onNext = { [weak self] in
            guard let self, !self.findBar.query.isEmpty else { return }
            self.selectedTab?.browserView.findText(self.findBar.query, forward: true, matchCase: false, findNext: true)
        }
        findBar.onPrevious = { [weak self] in
            guard let self, !self.findBar.query.isEmpty else { return }
            self.selectedTab?.browserView.findText(self.findBar.query, forward: false, matchCase: false, findNext: true)
        }
        findBar.onClose = { [weak self] in self?.hideFindBar() }
        contentContainer.addSubview(findBar, positioned: .above, relativeTo: nil)
    }

    private func buildSuggestions() {
        suggestionsView.onPick = { [weak self] suggestion in
            self?.acceptSuggestion(suggestion)
        }
        contentContainer.addSubview(suggestionsView, positioned: .above, relativeTo: findBar)
    }

    private var suggestionAnchor: NSRect {
        toolbarView.convert(addressBox.frame, to: contentContainer)
    }

    private func acceptSuggestion(_ suggestion: Suggestion) {
        suggestionsView.dismiss()
        SuggestionEngine.shared.cancel()
        addressField.stringValue = ForgeURL.display(for: suggestion.target)
        navigate(to: suggestion.target)
        window?.makeFirstResponder(nil)
    }

    private func refreshSuggestions() {
        let query = addressField.stringValue.trimmingCharacters(in: .whitespaces)
        suggestionQuery = query

        guard !query.isEmpty else {
            SuggestionEngine.shared.cancel()
            suggestionsView.dismiss()
            return
        }

        var items = [primarySuggestion(for: query)]
        items.append(contentsOf: SuggestionEngine.shared.local(for: query))
        suggestionsView.present(items, anchor: suggestionAnchor)

        suggestionDebounce?.invalidate()
        suggestionDebounce = Timer.scheduledTimer(withTimeInterval: 0.14, repeats: false) { [weak self] _ in
            guard let self else { return }
            SuggestionEngine.shared.remote(for: query) { [weak self] phrases in
                guard let self, self.suggestionQuery == query, !phrases.isEmpty else { return }
                var merged = [self.primarySuggestion(for: query)]
                merged.append(contentsOf: SuggestionEngine.shared.local(for: query, limit: 3))
                let engine = SearchEngines.current
                for phrase in phrases where phrase.lowercased() != query.lowercased() {
                    merged.append(Suggestion(kind: .search,
                                             title: phrase,
                                             subtitle: engine.name,
                                             target: engine.url(for: phrase)))
                }
                self.suggestionsView.present(Array(merged.prefix(9)), anchor: self.suggestionAnchor)
            }
        }
    }

    private func primarySuggestion(for query: String) -> Suggestion {
        let engine = SearchEngines.current
        let resolved = AddressResolver.resolve(query)
        if resolved == engine.url(for: query) {
            return Suggestion(kind: .search,
                              title: query,
                              subtitle: "Search with " + engine.name,
                              target: resolved)
        }
        return Suggestion(kind: .navigate,
                          title: ForgeURL.display(for: resolved),
                          subtitle: "Open directly",
                          target: resolved)
    }

    private func positionFindBar() {
        let width: CGFloat = 430
        findBar.frame = NSRect(x: contentContainer.bounds.width - width - 18,
                               y: contentContainer.bounds.height - 52,
                               width: width, height: 40)
    }

    @objc func handleFind() {
        positionFindBar()
        findBar.isHidden = false
        findVisible = true
        Theme.animate(0.2) { self.findBar.animator().alphaValue = 1 }
        findBar.focus()
    }

    private func hideFindBar() {
        findVisible = false
        selectedTab?.browserView.stopFinding(true)
        Theme.animate(0.16) { self.findBar.animator().alphaValue = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { self.findBar.isHidden = true }
        window?.makeFirstResponder(nil)
    }

    @objc func handleFindNext() { findBar.onNext?() }
    @objc func handleFindPrevious() { findBar.onPrevious?() }

    private var fieldEditorIsFocused: Bool {
        window?.firstResponder is NSTextView
    }

    @objc func handleUndo() {
        if fieldEditorIsFocused { (window?.firstResponder as? NSTextView)?.undoManager?.undo() }
        else { selectedTab?.browserView.editUndo() }
    }

    @objc func handleRedo() {
        if fieldEditorIsFocused { (window?.firstResponder as? NSTextView)?.undoManager?.redo() }
        else { selectedTab?.browserView.editRedo() }
    }

    @objc func handleCut() {
        if let editor = window?.firstResponder as? NSTextView { editor.cut(nil) }
        else { selectedTab?.browserView.editCut() }
    }

    @objc func handleCopy() {
        if let editor = window?.firstResponder as? NSTextView { editor.copy(nil) }
        else { selectedTab?.browserView.editCopy() }
    }

    @objc func handlePaste() {
        if let editor = window?.firstResponder as? NSTextView { editor.paste(nil) }
        else { selectedTab?.browserView.editPaste() }
    }

    @objc func handleSelectAll() {
        if let editor = window?.firstResponder as? NSTextView { editor.selectAll(nil) }
        else { selectedTab?.browserView.editSelectAll() }
    }

    @objc func handleToggleFullScreen() { window?.toggleFullScreen(nil) }

    @objc func handleZoomIn() { selectedTab?.browserView.zoomIn() }
    @objc func handleZoomOut() { selectedTab?.browserView.zoomOut() }
    @objc func handleActualSize() { selectedTab?.browserView.resetZoom() }
    @objc func handleViewSource() { selectedTab?.browserView.viewSource() }
    @objc func handlePrint() { selectedTab?.browserView.printPage() }
    @objc func handleForceReload() { selectedTab?.browserView.reloadIgnoringCache() }
    @objc func handleStop() { selectedTab?.browserView.stopLoading() }
    @objc func handleHome() { navigate(to: "forge://home/") }

    @objc func handleNextTab() {
        guard !tabs.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % tabs.count
        refreshChrome()
    }

    @objc func handlePreviousTab() {
        guard !tabs.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + tabs.count) % tabs.count
        refreshChrome()
    }

    @objc func handleReopenClosedTab() {
        guard let closed = ClosedTabStore.shared.pop() else { return }
        newTab(url: closed.url)
    }

    @objc func handleBookmarkTab() {
        guard let tab = selectedTab, tab.url.hasPrefix("http") else { return }
        BookmarkStore.shared.toggle(title: tab.title, url: tab.url)
        pushState()
    }

    @objc func handleShowBookmarks() { newTab(url: "forge://home/bookmarks.html") }
    @objc func handleShowHistory() { newTab(url: "forge://home/history.html") }
    @objc func handleShowSettings() { newTab(url: "forge://home/settings.html") }
    @objc func handleShowDownloads() { newTab(url: "forge://home/downloads.html") }
    @objc func handleShowHelp() { newTab(url: "forge://home/help.html") }

    @objc func handleOpenTool(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? String else { return }
        newTab(url: url)
    }

    private func style(button: NSButton, glyph: String, action: Selector) {
        button.title = glyph
        button.font = .systemFont(ofSize: 15, weight: .regular)
        button.isBordered = false
        button.contentTintColor = Theme.bone
        button.target = self
        button.action = action
        button.wantsLayer = true
        button.layer?.cornerRadius = 7
    }

    private func layoutToolbar() {
        let h = Theme.Metrics.toolbarHeight
        let pad: CGFloat = 10
        let bw: CGFloat = 30
        let fieldH: CGFloat = 30
        let y = (h - fieldH) / 2
        var x = pad

        for button in [backButton, forwardButton, reloadButton] {
            button.frame = NSRect(x: x, y: y, width: bw, height: fieldH)
            x += bw + 2
        }
        x += 6

        let rightWidth: CGFloat = 30 + 6 + 46 + pad
        let counterWidth: CGFloat = 78
        let pillWidth: CGFloat = bypassPill.isHidden ? 0 : 150
        let fieldWidth = max(140, toolbarView.bounds.width - x - rightWidth - counterWidth - pillWidth - 16)

        addressBox.frame = NSRect(x: x, y: y, width: fieldWidth, height: fieldH)
        x += fieldWidth + 10

        if !bypassPill.isHidden {
            bypassPill.frame = NSRect(x: x, y: y + 6, width: 150, height: 18)
            x += 158
        }
        blockCounter.frame = NSRect(x: x, y: y + 7, width: counterWidth, height: 16)
        x += counterWidth + 6

        layoutButton.frame = NSRect(x: toolbarView.bounds.width - pad - 46 - 6 - 30, y: y, width: 30, height: fieldH)
        paletteButton.frame = NSRect(x: toolbarView.bounds.width - pad - 46, y: y, width: 46, height: fieldH)
    }

    private func startMonitors() {
        DevServerMonitor.shared.onChange = { [weak self] _ in self?.pushState() }
        DevServerMonitor.shared.start()

        FGStateStore.shared.setCommandHandler { [weak self] action, payload in
            self?.handlePageCommand(action: action, payload: payload)
            return ["ok": true]
        }

        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.pushState()
            self?.updateBlockCounter()
        }
        RunLoop.main.add(timer, forMode: .common)
        stateTimer = timer
        pushState()
    }

    // MARK: - Tabs

    @discardableResult
    func newTab(url: String, select: Bool = true) -> Tab {
        let tab = Tab(url: url)
        tab.browserView.browserDelegate = self
        tabs.append(tab)

        tab.browserView.translatesAutoresizingMaskIntoConstraints = true
        tab.browserView.autoresizingMask = [.width, .height]
        tab.browserView.frame = contentContainer.bounds
        tab.browserView.isHidden = true
        contentContainer.addSubview(tab.browserView, positioned: .below, relativeTo: findBar)

        if select { selectedIndex = tabs.count - 1 }
        refreshChrome()
        return tab
    }

    private func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        closeTab(at: index)
    }

    func closeTab(at index: Int) {
        guard index >= 0, index < tabs.count else { return }
        let tab = tabs.remove(at: index)
        ClosedTabStore.shared.push(url: tab.url, title: tab.title)
        tab.browserView.closeBrowser()
        tab.browserView.removeFromSuperview()

        if tabs.isEmpty {
            newTab(url: "forge://home/")
            return
        }
        selectedIndex = min(selectedIndex, tabs.count - 1)
        refreshChrome()
    }

    private func selectTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        selectedIndex = index
        refreshChrome()
    }

    private func refreshChrome() {
        for (index, tab) in tabs.enumerated() {
            tab.browserView.isHidden = index != selectedIndex
            if index == selectedIndex { tab.browserView.frame = contentContainer.bounds }
        }
        if findVisible { positionFindBar() }
        tabStrip.update(with: tabs, selectedIndex: selectedIndex)
        updateToolbarState()
    }

    private func updateToolbarState() {
        guard let tab = selectedTab else { return }
        let shown = ForgeURL.display(for: tab.url)
        if addressField.stringValue != shown && window?.firstResponder !== addressField.currentEditor() {
            addressField.stringValue = shown
        }
        backButton.isEnabled = tab.canGoBack
        forwardButton.isEnabled = tab.canGoForward
        backButton.contentTintColor = tab.canGoBack ? Theme.bone : Theme.line2
        forwardButton.contentTintColor = tab.canGoForward ? Theme.bone : Theme.line2
        reloadButton.title = tab.isLoading ? "✕" : "⟳"
        window?.title = tab.displayTitle.isEmpty ? "Forge" : "Forge — " + tab.displayTitle

        let wasHidden = bypassPill.isHidden
        if tab.ignoresCertificateErrors {
            bypassPill.stringValue = "⚠︎  CERT CHECKS OFF"
            bypassPill.isHidden = false
        } else {
            bypassPill.isHidden = true
        }
        if wasHidden != bypassPill.isHidden { layoutToolbar() }
        updateBlockCounter()
    }

    private func updateBlockCounter() {
        let value = "\(FGAdblock.shared.blockedCount) blocked"
        if blockCounter.stringValue != value { blockCounter.stringValue = value }
    }

    // MARK: - Actions

    @objc func handleNewTab() {
        newTab(url: "forge://home/")
        window?.makeFirstResponder(addressField)
    }

    @objc func handleCloseTab() { closeTab(at: selectedIndex) }
    @objc func handleBack() { selectedTab?.browserView.goBack() }
    @objc func handleForward() { selectedTab?.browserView.goForward() }

    @objc func handleReload() {
        guard let tab = selectedTab else { return }
        if tab.isLoading { tab.browserView.stopLoading() } else { tab.browserView.reload() }
    }

    @objc func handleFocusAddress() { window?.makeFirstResponder(addressField) }

    @objc func handleToggleOrientation() {
        orientation = orientation.flipped
    }

    @objc private func handleAddressSubmit() {
        if let selection = suggestionsView.selected, suggestionsView.isPresenting {
            acceptSuggestion(selection)
            return
        }
        suggestionsView.dismiss()
        SuggestionEngine.shared.cancel()
        let resolved = AddressResolver.resolve(addressField.stringValue)
        selectedTab?.browserView.loadURL(resolved)
        window?.makeFirstResponder(nil)
    }

    @objc func handleTogglePalette() {
        guard let window = window else { return }
        palette.toggle(relativeTo: window)
    }

    @objc func handleToggleCertBypass() {
        guard let tab = selectedTab else { return }
        tab.ignoresCertificateErrors.toggle()
        refreshChrome()
    }

    @objc func handleShowDevTools() { selectedTab?.browserView.showDevTools() }

    func navigate(to url: String) { selectedTab?.browserView.loadURL(url) }

    func controlTextDidBeginEditing(_ obj: Notification) { addressBox.isFocused = true }

    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as AnyObject?) === addressField else { return }
        refreshSuggestions()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        addressBox.isFocused = false
        suggestionDebounce?.invalidate()
        SuggestionEngine.shared.cancel()
        suggestionsView.dismiss()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === addressField, suggestionsView.isPresenting else { return false }
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            suggestionsView.move(by: 1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            suggestionsView.move(by: -1)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            suggestionsView.dismiss()
            return true
        default:
            return false
        }
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        layoutToolbar()
    }

    // MARK: - Palette

    private func configurePalette() {
        palette.commandProvider = { [weak self] in
            guard let self else { return [] }
            var commands: [PaletteCommand] = [
                PaletteCommand(id: "new-tab", title: "New Tab", subtitle: "Open the Forge landing page") { [weak self] in
                    self?.handleNewTab()
                },
                PaletteCommand(id: "close-tab", title: "Close Tab", subtitle: "Close the current tab") { [weak self] in
                    self?.handleCloseTab()
                },
                PaletteCommand(
                    id: "orientation",
                    title: self.orientation == .horizontal ? "Switch to Vertical Tabs" : "Switch to Horizontal Tabs",
                    subtitle: "Change the tab strip layout"
                ) { [weak self] in
                    self?.handleToggleOrientation()
                },
                PaletteCommand(id: "reload", title: "Reload", subtitle: "Reload the current page") { [weak self] in
                    self?.selectedTab?.browserView.reload()
                },
                PaletteCommand(id: "hard-reload", title: "Hard Reload", subtitle: "Reload ignoring cache") { [weak self] in
                    self?.selectedTab?.browserView.reloadIgnoringCache()
                },
                PaletteCommand(id: "devtools", title: "Open DevTools", subtitle: "Chromium DevTools for this tab") { [weak self] in
                    self?.handleShowDevTools()
                },
                PaletteCommand(id: "home", title: "Open Landing Page", subtitle: "forge://home/") { [weak self] in
                    self?.navigate(to: "forge://home/")
                },
                PaletteCommand(
                    id: "cert-bypass",
                    title: (self.selectedTab?.ignoresCertificateErrors ?? false)
                        ? "Disable Certificate Bypass (this tab)"
                        : "Ignore Certificate Errors (this tab)",
                    subtitle: "Scoped to this tab, shows a persistent warning while active"
                ) { [weak self] in
                    self?.handleToggleCertBypass()
                }
            ]

            for tool in DevTools.all {
                commands.append(PaletteCommand(id: "tool-" + tool.id, title: tool.name, subtitle: "Developer utility") { [weak self] in
                    self?.newTab(url: tool.url)
                })
            }
            for server in DevServerMonitor.shared.servers {
                commands.append(PaletteCommand(id: "port-\(server.port)", title: "Open localhost:\(server.port)", subtitle: server.processName) { [weak self] in
                    self?.newTab(url: server.url)
                })
            }
            for engine in SearchEngines.all {
                commands.append(PaletteCommand(id: "engine-" + engine.id, title: "Search with " + engine.name, subtitle: "Set the default search engine") {
                    SearchEngines.current = engine
                })
            }
            return commands
        }
    }

    // MARK: - Page bridge

    private func handlePageCommand(action: String, payload: [String: Any]) {
        switch action {
        case "navigate":
            if let url = payload["url"] as? String { navigate(to: AddressResolver.resolve(url)) }
        case "newTab":
            if let url = payload["url"] as? String { newTab(url: AddressResolver.resolve(url)) }
        case "search":
            if let query = payload["query"] as? String { navigate(to: SearchEngines.current.url(for: query)) }
        case "setSearchEngine":
            if let id = payload["id"] as? String, let engine = SearchEngines.engine(withID: id) {
                SearchEngines.current = engine
                pushState()
            }
        case "openPalette":
            handleTogglePalette()
        case "setTabOrientation":
            if let value = payload["value"] as? String, let next = TabOrientation(rawValue: value) {
                orientation = next
            }
        case "removeBookmark":
            if let url = payload["url"] as? String { BookmarkStore.shared.remove(url: url); pushState() }
        case "clearHistory":
            HistoryStore.shared.clear(); pushState()
        case "clearDownloads":
            FGDownloads.shared.clearCompleted(); pushState()
        case "revealDownload":
            if let path = payload["path"] as? String, !path.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        case "setTrays":
            if let raw = payload["trays"] as? [[String: Any]] {
                let parsed: [Trays.Tray] = raw.compactMap { item in
                    guard let name = item["name"] as? String,
                          let sites = item["sites"] as? [[String: String]] else { return nil }
                    return Trays.Tray(name: name, sites: sites.compactMap {
                        guard let t = $0["title"], let u = $0["url"] else { return nil }
                        return Trays.Site(title: t, url: u)
                    })
                }
                if !parsed.isEmpty { Trays.all = parsed; pushState() }
            }
        default:
            break
        }
    }

    private func pushState() {
        let store = FGStateStore.shared
        let blocked = FGAdblock.shared.blockedCount
        let bytes = FGAdblock.shared.estimatedBytesSaved
        StatsStore.shared.commitSessionCounters(blocked: blocked, bytes: bytes)

        store.setValue(SearchEngines.all.map { ["id": $0.id, "name": $0.name] }, forStateKey: "searchEngines")
        store.setValue(SearchEngines.current.id, forStateKey: "currentSearchEngine")
        store.setValue(Trays.all.map { tray in
            ["name": tray.name, "sites": tray.sites.map { ["title": $0.title, "url": $0.url] }]
        }, forStateKey: "trays")
        store.setValue(DevServerMonitor.shared.servers.map {
            ["port": $0.port, "process": $0.processName, "url": $0.url]
        }, forStateKey: "devServers")
        store.setValue(DevTools.all.map { ["id": $0.id, "name": $0.name, "url": $0.url, "group": $0.group] }, forStateKey: "tools")

        let statsPayload: [String: Any] = [
            "lifetimeBlocked": StatsStore.shared.lifetimeBlocked,
            "lifetimeBytesSaved": StatsStore.shared.lifetimeBytesSaved,
            "estimatedSecondsSaved": StatsStore.estimatedSecondsSaved(
                fromBytes: StatsStore.shared.lifetimeBytesSaved,
                blockedRequests: StatsStore.shared.lifetimeBlocked
            )
        ]
        store.setValue(statsPayload, forStateKey: "stats")
        store.setValue(BookmarkStore.shared.all.map { ["title": $0.title, "url": $0.url] }, forStateKey: "bookmarks")
        store.setValue(HistoryStore.shared.recent(300).map {
            ["title": $0.title, "url": $0.url, "at": ISO8601DateFormatter().string(from: $0.visitedAt)]
        }, forStateKey: "history")
        store.setValue(orientation.rawValue, forStateKey: "tabOrientation")
        store.setValue(FGDownloads.shared.snapshot(), forStateKey: "downloads")
        store.setValue([
            "popupsBlocked": FGAdblock.shared.blockedPopupCount,
            "lists": FGAdblock.shared.listCount
        ], forStateKey: "shields")
        store.setValue(FGEngine.cefVersion(), forStateKey: "cefVersion")
    }

    // MARK: - FGBrowserViewDelegate

    func browserView(_ view: FGBrowserView, didChangeURL url: String) {
        guard let tab = tabs.first(where: { $0.browserView === view }) else { return }
        tab.url = url
        if tab.favicon == nil, let cached = FaviconStore.shared.icon(for: url) {
            tab.favicon = cached
            tabStrip.update(with: tabs, selectedIndex: selectedIndex)
        }
        if tab === selectedTab { updateToolbarState() }
    }

    func browserView(_ view: FGBrowserView, didUpdateFindMatchCount count: Int, active activeOrdinal: Int) {
        findBar.setMatches(count: count, active: activeOrdinal)
    }

    func browserView(_ view: FGBrowserView, didChangeFavicon favicon: NSImage?) {
        guard let tab = tabs.first(where: { $0.browserView === view }) else { return }
        tab.favicon = favicon
        if let favicon { FaviconStore.shared.store(favicon, for: tab.url) }
        tabStrip.update(with: tabs, selectedIndex: selectedIndex)
    }

    func browserView(_ view: FGBrowserView, didChangeTitle title: String) {
        guard let tab = tabs.first(where: { $0.browserView === view }) else { return }
        tab.title = title
        HistoryStore.shared.record(url: tab.url, title: title)
        tabStrip.update(with: tabs, selectedIndex: selectedIndex)
        if tab === selectedTab { updateToolbarState() }
    }

    func browserView(_ view: FGBrowserView, didChangeLoading loading: Bool, canGoBack: Bool, canGoForward: Bool) {
        guard let tab = tabs.first(where: { $0.browserView === view }) else { return }
        tab.isLoading = loading
        tab.canGoBack = canGoBack
        tab.canGoForward = canGoForward
        tabStrip.update(with: tabs, selectedIndex: selectedIndex)
        if tab === selectedTab { updateToolbarState() }
    }

    func browserView(_ view: FGBrowserView, didFailWithMessage message: String, url: String) {
        NSLog("[forge] load failed for %@: %@", url, message)
    }

    func browserViewDidRequestCommandPalette(_ view: FGBrowserView) {
        handleTogglePalette()
    }

    func browserView(_ view: FGBrowserView, didRequestNewTabWithURL url: String, disposition: FGNavigationDisposition) {
        newTab(url: url, select: disposition != .newBackgroundTab)
    }
}
