import AppKit

final class BrowserWindowController: NSWindowController, FGBrowserViewDelegate, NSTextFieldDelegate {

    private(set) var isPrivate = false
    private var tabs: [Tab] = []
    private var groups: [TabGroup] = []
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
    private let privatePill = NSTextField(labelWithString: "")
    private let blockCounter = NSTextField(labelWithString: "")

    private let sidebar = SidebarView()
    private let nowPlayingBar = NowPlayingBar()
    private var mediaTabID: UUID?
    private let palette = CommandPaletteController()
    private let findBar = FindBar()
    private let suggestionsView = OmniboxSuggestionsView()
    private let statsOverlay = StatsOverlayView()
    private var statsVisible = false
    private var statsTimer: Timer?
    private var audioTimer: Timer?
    private var pageRows: [(String, String)] = []
    private var audioRows: [(String, String)] = []
    private var videoRows: [(String, String)] = []
    private var spectrumValues: [Double] = []
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

    var homeURL: String { isPrivate ? "forge://home/private.html" : "forge://home/" }

    convenience init() {
        self.init(isPrivate: false)
    }

    convenience init(isPrivate: Bool) {
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
        self.isPrivate = isPrivate
        window.title = isPrivate ? "Forge Private" : "Forge"
        buildInterface()
        configurePalette()
        startMonitors()
        newTab(url: homeURL)
    }

    private func buildInterface() {
        guard let root = window?.contentView else { return }
        root.wantsLayer = true
        root.layer?.backgroundColor = Theme.void.cgColor
        if isPrivate {
            addressBox.accentOverride = Theme.privateAccent
        }

        chrome.autoresizingMask = [.width, .height]
        chrome.frame = root.bounds
        root.addSubview(chrome)

        tabStrip.onSelect = { [weak self] id in self?.selectTab(id: id) }
        tabStrip.onClose = { [weak self] id in self?.closeTab(id: id) }
        tabStrip.onNewTab = { [weak self] in self?.handleNewTab() }
        tabStrip.onToggleGroup = { [weak self] id in self?.toggleGroupCollapsed(id) }
        tabStrip.menuProvider = { [weak self] id in self?.tabContextMenu(for: id) }
        tabStrip.overflowMenuProvider = { [weak self] in self?.tabOverflowMenu() }

        toolbarView.wantsLayer = true
        toolbarView.layer?.backgroundColor = Theme.ink.cgColor
        toolbarView.onLayout = { [weak self] in self?.layoutToolbar() }

        dividerView.wantsLayer = true
        dividerView.layer?.backgroundColor = Theme.line.cgColor

        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = Theme.void.cgColor

        chrome.addSubview(contentContainer)
        chrome.addSubview(sidebar)
        chrome.addSubview(nowPlayingBar)
        chrome.addSubview(tabStrip)
        chrome.addSubview(toolbarView)
        chrome.addSubview(dividerView)

        chrome.tabStrip = tabStrip
        chrome.toolbar = toolbarView
        chrome.content = contentContainer
        chrome.divider = dividerView
        chrome.sidebar = sidebar
        chrome.nowPlaying = nowPlayingBar
        buildSidebar()
        nowPlayingBar.isHidden = true
        buildNowPlaying()

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

        privatePill.stringValue = "PRIVATE"
        privatePill.font = .systemFont(ofSize: 10, weight: .heavy)
        privatePill.textColor = Theme.void
        privatePill.alignment = .center
        privatePill.wantsLayer = true
        privatePill.layer?.backgroundColor = Theme.privateAccent.cgColor
        privatePill.layer?.cornerRadius = 5
        privatePill.layer?.shadowColor = Theme.privateAccent.cgColor
        privatePill.layer?.shadowOpacity = 0.45
        privatePill.layer?.shadowRadius = 10
        privatePill.layer?.shadowOffset = .zero
        privatePill.isHidden = !isPrivate

        blockCounter.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        blockCounter.textColor = Theme.moss

        for view in [backButton, forwardButton, reloadButton, addressBox, privatePill, bypassPill, blockCounter, layoutButton, paletteButton] {
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

    private func buildSidebar() {
        sidebar.onNavigate = { [weak self] url in self?.navigate(to: url) }
        sidebar.onSelectTab = { [weak self] id in self?.selectTab(id: id) }
        sidebar.onCloseTab = { [weak self] id in self?.closeTab(id: id) }
        sidebar.onMuteTab = { [weak self] id in self?.toggleMute(id) }
        sidebar.onHome = { [weak self] in self?.handleHome() }
        sidebar.onSettings = { [weak self] in self?.handleShowSettings() }
        sidebar.onNewTab = { [weak self] in self?.handleNewTab() }
        sidebar.onLayoutChange = { [weak self] in
            guard let self else { return }
            self.chrome.sidebarWidth = self.sidebar.preferredWidth
        }
        chrome.sidebarWidth = sidebar.preferredWidth
    }

    @objc func handleToggleSidebar() {
        sidebar.toggle()
        chrome.sidebarWidth = sidebar.preferredWidth
    }

    private func buildNowPlaying() {
        nowPlayingBar.onTogglePlay = { [weak self] in self?.runMediaCommand(MediaProbe.toggle) }
        nowPlayingBar.onToggleMute = { [weak self] in self?.runMediaCommand(MediaProbe.toggleMute) }
        nowPlayingBar.onSeekBack = { [weak self] in self?.runMediaCommand(MediaProbe.seek(-10)) }
        nowPlayingBar.onSeekForward = { [weak self] in self?.runMediaCommand(MediaProbe.seek(10)) }
        nowPlayingBar.onReveal = { [weak self] in
            guard let self, let id = self.mediaTabID else { return }
            self.selectTab(id: id)
        }
    }

    private var mediaTab: Tab? {
        guard let id = mediaTabID else { return nil }
        return tabs.first { $0.id == id }
    }

    private func runMediaCommand(_ script: String) {
        guard let tab = mediaTab else { return }
        tab.browserView.evaluate(script) { [weak self] _ in
            self?.pollMedia()
        }
    }

    private func pollMedia() {
        for tab in tabs where tab.url.hasPrefix("http") {
            tab.browserView.evaluate(MediaProbe.script) { [weak self] result in
                guard let self else { return }
                if let payload = result as? [String: Any] {
                    tab.media = NowPlaying(payload)
                } else {
                    tab.media = nil
                }
                self.refreshNowPlaying()
            }
        }
        if tabs.allSatisfy({ !$0.url.hasPrefix("http") }) {
            refreshNowPlaying()
        }
    }

    private func refreshNowPlaying() {
        let playing = tabs.first { $0.media?.playing == true }
        let anyMedia = playing ?? tabs.first { $0.media != nil }

        guard let tab = anyMedia, let state = tab.media else {
            mediaTabID = nil
            chrome.nowPlayingVisible = false
            return
        }

        mediaTabID = tab.id
        nowPlayingBar.apply(state)
        chrome.nowPlayingVisible = true
    }

    private func buildSuggestions() {
        suggestionsView.onPick = { [weak self] suggestion in
            self?.acceptSuggestion(suggestion)
        }
        contentContainer.addSubview(suggestionsView, positioned: .above, relativeTo: findBar)
        contentContainer.addSubview(statsOverlay, positioned: .above, relativeTo: suggestionsView)
    }

    @objc func handleToggleStats() {
        statsVisible.toggle()
        if statsVisible {
            statsOverlay.isHidden = false
            statsOverlay.alphaValue = 0
            refreshStats()
            refreshAudio()
            Theme.animate(0.16) { self.statsOverlay.animator().alphaValue = 1 }
            let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.refreshStats() }
            RunLoop.main.add(timer, forMode: .common)
            statsTimer = timer

            let audio = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in self?.refreshAudio() }
            RunLoop.main.add(audio, forMode: .common)
            audioTimer = audio
        } else {
            statsTimer?.invalidate()
            statsTimer = nil
            audioTimer?.invalidate()
            audioTimer = nil
            Theme.animate(0.14) { self.statsOverlay.animator().alphaValue = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                if !self.statsVisible { self.statsOverlay.isHidden = true }
            }
        }
    }

    private func refreshStats() {
        guard statsVisible, let tab = selectedTab else { return }
        tab.browserView.evaluate(StatsProbe.script) { [weak self] result in
            guard let self, self.statsVisible else { return }
            self.pageRows = self.makePageRows(result as? [String: Any] ?? [:], tab: tab)
            self.renderStats()
        }
    }

    private func refreshAudio() {
        guard statsVisible, let tab = selectedTab else { return }
        tab.browserView.evaluate(AudioProbeScript.call) { [weak self] result in
            guard let self, self.statsVisible else { return }
            guard let payload = result as? [String: Any], let snapshot = AudioSnapshot(payload) else {
                self.audioRows = []
                self.videoRows = []
                self.spectrumValues = []
                self.renderStats()
                return
            }
            self.audioRows = self.makeAudioRows(snapshot)
            self.spectrumValues = snapshot.spectrum
            self.videoRows = VideoSnapshot(payload["video"] as? [String: Any])
                .map { self.makeVideoRows($0, tab: tab) } ?? []
            self.renderStats()
        }
    }

    private func makePageRows(_ page: [String: Any], tab: Tab) -> [(String, String)] {
        func number(_ key: String) -> Double { (page[key] as? NSNumber)?.doubleValue ?? 0 }
        let adblock = FGAdblock.shared

        return [
            ("origin", page["origin"] as? String ?? "—"),
            ("dom nodes", number("nodes") > 0 ? String(Int(number("nodes"))) : "—"),
            ("requests", String(Int(number("resources")))),
            ("transferred", StatsFormat.bytes(number("transferred"))),
            ("ttfb", StatsFormat.millis(number("ttfb"))),
            ("dom ready", StatsFormat.millis(number("dcl"))),
            ("load", StatsFormat.millis(number("load"))),
            ("js heap", StatsFormat.bytes(number("heap"))),
            ("subframes", String(Int(number("frames")))),
            ("blocked here", String(tab.browserView.blockedCountForTab)),
            ("ads defused", String(Int(number("defused")))),
            ("hidden here", String(tab.browserView.cosmeticSelectorCount)),
            ("blocked total", String(adblock.blockedCount)),
            ("requests seen", String(adblock.requestsSeen)),
            ("popups blocked", String(adblock.blockedPopupCount)),
            ("filter rules", String(adblock.ruleCount)),
            ("open tabs", String(tabs.count)),
            ("helper processes", String(FGEngine.helperProcessCount())),
            ("browser memory", StatsFormat.bytes(Double(FGEngine.memoryFootprint()))),
            ("chromium", FGEngine.cefVersion())
        ]
    }

    private func kilohertz(_ value: Double) -> String {
        guard value > 0 else { return "—" }
        let k = value / 1000
        return (k == k.rounded() ? String(format: "%.0f", k) : String(format: "%.1f", k)) + " kHz"
    }

    private func makeAudioRows(_ snapshot: AudioSnapshot) -> [(String, String)] {
        let device = FGAudioDevice.currentOutput()
        let deviceRate = (device["sampleRate"] as? NSNumber)?.doubleValue ?? 0
        let bitDepth = (device["bitDepth"] as? NSNumber)?.intValue ?? 0
        let mixDepth = (device["mixDepth"] as? NSNumber)?.intValue ?? 0
        let sampleFormat = device["sampleFormat"] as? String ?? ""
        let deviceChannels = (device["channels"] as? NSNumber)?.intValue ?? 0
        let name = device["name"] as? String ?? "Unknown"
        let transport = device["transport"] as? String ?? "—"

        var rows: [(String, String)] = [
            ("source", snapshot.host),
            ("codec", snapshot.codecLabel),
            ("bitrate", snapshot.kbps > 0 ? "\(snapshot.kbps) kbps" : "measuring…"),
            ("codec rate", snapshot.nativeRate.map(kilohertz) ?? "unknown"),
            ("mix rate", kilohertz(snapshot.contextRate)),
            ("channels", snapshot.channels > 0 ? String(snapshot.channels) : "—"),
            ("output", name),
            ("device rate", kilohertz(deviceRate)),
            ("bit depth", bitDepth > 0
                ? "\(bitDepth)-bit " + sampleFormat
                : (mixDepth > 0 ? "\(mixDepth)-bit mix" : "—")),
            ("transport", transport + (deviceChannels > 0 ? " · \(deviceChannels)ch" : ""))
        ]

        if let native = snapshot.nativeRate, deviceRate > 0 {
            rows.append(("resampling", abs(native - deviceRate) < 1
                ? "none · " + kilohertz(deviceRate)
                : kilohertz(native) + " → " + kilohertz(deviceRate)))
        } else {
            rows.append(("resampling", "unknown"))
        }
        return rows
    }

    private func makeVideoRows(_ snapshot: VideoSnapshot, tab: Tab) -> [(String, String)] {
        let properties = tab.browserView.mediaProperties
        let decoder = properties["kVideoDecoderName"] as? String
            ?? properties["video_decoder_name"] as? String
        let platform = properties["kIsPlatformVideoDecoder"] ?? properties["is_platform_video_decoder"]
        let hardware: String
        if let flag = platform as? Bool {
            hardware = flag ? "hardware" : "software"
        } else if let text = platform as? String {
            hardware = text == "true" ? "hardware" : "software"
        } else {
            hardware = "unknown"
        }

        let dropRate = snapshot.totalFrames > 0
            ? Double(snapshot.dropped) / Double(snapshot.totalFrames) * 100
            : 0

        return [
            ("codec", snapshot.codecLabel),
            ("resolution", snapshot.resolutionLabel),
            ("framerate", snapshot.fps > 0 ? "\(snapshot.fps) fps" : "—"),
            ("bitrate", snapshot.kbps > 0 ? "\(snapshot.kbps) kbps" : "measuring…"),
            ("bit depth", snapshot.depthLabel),
            ("dropped", snapshot.totalFrames > 0
                ? String(format: "%d of %d · %.2f%%", snapshot.dropped, snapshot.totalFrames, dropRate)
                : "—"),
            ("decoder", decoder ?? "unknown"),
            ("decode path", hardware),
            ("display range", snapshot.displayHDR ? "HDR capable" : "SDR")
        ]
    }

    private func renderStats() {
        var sections: [(String, [(String, String)])] = [("STATS FOR NERDS", pageRows)]
        if !audioRows.isEmpty { sections.append(("AUDIO PATH", audioRows)) }
        if !videoRows.isEmpty { sections.append(("VIDEO PIPELINE", videoRows)) }
        statsOverlay.apply(sections: sections, spectrum: audioRows.isEmpty ? [] : spectrumValues)
        positionStats()
    }

    private func positionStats() {
        let width: CGFloat = 336
        let available = max(160, contentContainer.bounds.height - 36)
        let height = min(statsOverlay.contentHeight + 2, available)
        statsOverlay.frame = NSRect(x: contentContainer.bounds.width - width - 18,
                                    y: contentContainer.bounds.height - height - 18,
                                    width: width, height: height)
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
    @objc func handleHome() { navigate(to: homeURL) }

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

    func addCurrentTabToTray(_ name: String?) {
        guard let tab = selectedTab, tab.url.hasPrefix("http") else { return }
        Trays.addSite(title: tab.title, url: tab.url, tray: name)
        pushState(force: true)
    }

    @objc func handleAddShortcut() { addCurrentTabToTray(nil) }

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
        let privateWidth: CGFloat = privatePill.isHidden ? 0 : 74
        let fieldWidth = max(140, toolbarView.bounds.width - x - rightWidth - counterWidth - pillWidth - privateWidth - 16)

        addressBox.frame = NSRect(x: x, y: y, width: fieldWidth, height: fieldH)
        x += fieldWidth + 10

        if !privatePill.isHidden {
            privatePill.frame = NSRect(x: x, y: y + 6, width: 66, height: 18)
            x += 74
        }

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
        DevServerMonitor.shared.onRestart = { [weak self] server in
            self?.reloadTabs(onPort: server.port)
        }
        DevServerMonitor.shared.start()

        FGStateStore.shared.setCommandHandler { [weak self] action, payload in
            self?.handlePageCommand(action: action, payload: payload)
            return ["ok": true]
        }

        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.pushState()
            self?.updateBlockCounter()
            self?.pollMedia()
        }
        RunLoop.main.add(timer, forMode: .common)
        stateTimer = timer
        pushState(force: true)
    }

    // MARK: - Tabs

    @discardableResult
    func newTab(url: String, select: Bool = true) -> Tab {
        let tab = Tab(url: url, isPrivate: isPrivate)
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

    func closeTab(id: UUID) {
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
            newTab(url: homeURL)
            return
        }
        selectedIndex = min(selectedIndex, tabs.count - 1)
        pruneGroups()
        selectFirstVisibleTab()
        refreshChrome()
    }

    var tabGroups: [TabGroup] { groups }

    var selectedTabGroupID: UUID? { selectedTab?.groupID }

    private func reorderIntoGroups() {
        let selectedID = selectedTab?.id
        var result: [Tab] = []
        var placed = Set<UUID>()
        for tab in tabs where !placed.contains(tab.id) {
            if let groupID = tab.groupID {
                for member in tabs where member.groupID == groupID && !placed.contains(member.id) {
                    result.append(member)
                    placed.insert(member.id)
                }
            } else {
                result.append(tab)
                placed.insert(tab.id)
            }
        }
        tabs = result
        if let selectedID, let index = tabs.firstIndex(where: { $0.id == selectedID }) {
            selectedIndex = index
        }
    }

    private func pruneGroups() {
        let live = Set(tabs.compactMap { $0.groupID })
        groups.removeAll { !live.contains($0.id) }
    }

    private func selectFirstVisibleTab() {
        let collapsed = Set(groups.filter { $0.isCollapsed }.map { $0.id })
        if let index = tabs.firstIndex(where: { tab in
            guard let groupID = tab.groupID else { return true }
            return !collapsed.contains(groupID)
        }) {
            selectedIndex = index
        }
    }

    func addSelectedTabToGroup(_ id: UUID) {
        guard let tab = selectedTab else { return }
        tab.groupID = id
        if let index = groups.firstIndex(where: { $0.id == id }) { groups[index].isCollapsed = false }
        reorderIntoGroups()
        pruneGroups()
        refreshChrome()
    }

    @objc func handleDuplicateTab() {
        guard let id = selectedTab?.id else { return }
        duplicateTab(id)
    }

    @objc func handleToggleMuteTab() {
        guard let id = selectedTab?.id else { return }
        toggleMute(id)
    }

    @objc func handleCloseOtherTabs() {
        guard let id = selectedTab?.id else { return }
        closeOtherTabs(id)
    }

    @objc func handleCloseTabsToTheLeft() {
        guard let id = selectedTab?.id else { return }
        closeTabsToTheLeft(id)
    }

    @objc func handleCloseTabsToTheRight() {
        guard let id = selectedTab?.id else { return }
        closeTabsToTheRight(id)
    }

    @objc func handleNewTabGroup() {
        guard let tab = selectedTab else { return }
        let group = TabGroup(name: "Group \(groups.count + 1)", colorIndex: groups.count)
        groups.append(group)
        tab.groupID = group.id
        reorderIntoGroups()
        refreshChrome()
    }

    @objc func handleUngroupTab() {
        guard let tab = selectedTab, tab.groupID != nil else { return }
        tab.groupID = nil
        reorderIntoGroups()
        pruneGroups()
        refreshChrome()
    }

    @objc func handleToggleGroupCollapsed() {
        guard let id = selectedTab?.groupID else { return }
        toggleGroupCollapsed(id)
    }

    func toggleGroupCollapsed(_ id: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].isCollapsed.toggle()
        if groups[index].isCollapsed, selectedTab?.groupID == id {
            selectFirstVisibleTab()
        }
        refreshChrome()
    }

    @objc func handleCloseGroup() {
        guard let id = selectedTab?.groupID else { return }
        let doomed = tabs.filter { $0.groupID == id }.map { $0.id }
        for tabID in doomed { closeTab(id: tabID) }
        pruneGroups()
        refreshChrome()
    }

    private func reloadTabs(onPort port: Int) {
        let needles = ["localhost:\(port)", "127.0.0.1:\(port)", "[::1]:\(port)"]
        for tab in tabs where needles.contains(where: { tab.url.contains($0) }) {
            tab.browserView.reloadIgnoringCache()
        }
    }

    private func tabIndex(_ id: UUID) -> Int? {
        tabs.firstIndex { $0.id == id }
    }

    func duplicateTab(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        newTab(url: tab.url)
    }

    func duplicateInPrivateWindow(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        (NSApp.delegate as? ForgeAppDelegate)?.presentPrivateWindow(with: tab.url)
    }

    func toggleMute(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        tab.isMuted.toggle()
        refreshChrome()
    }

    func closeOtherTabs(_ id: UUID) {
        for target in tabs.map({ $0.id }) where target != id { closeTab(id: target) }
    }

    func closeTabsToTheLeft(_ id: UUID) {
        guard let index = tabIndex(id), index > 0 else { return }
        for target in tabs.prefix(index).map({ $0.id }) { closeTab(id: target) }
    }

    func closeTabsToTheRight(_ id: UUID) {
        guard let index = tabIndex(id), index + 1 < tabs.count else { return }
        for target in tabs.suffix(from: index + 1).map({ $0.id }) { closeTab(id: target) }
    }

    private func tabContextMenu(for id: UUID) -> NSMenu? {
        guard let index = tabIndex(id) else { return nil }
        let tab = tabs[index]
        let menu = NSMenu()

        menu.addItem(ClosureMenuItem("New Tab") { [weak self] in self?.handleNewTab() })
        menu.addItem(ClosureMenuItem("Duplicate Tab") { [weak self] in self?.duplicateTab(id) })
        menu.addItem(ClosureMenuItem("Duplicate in Private Window") { [weak self] in
            self?.duplicateInPrivateWindow(id)
        })
        menu.addItem(.separator())

        menu.addItem(ClosureMenuItem(tab.isMuted ? "Unmute Tab" : "Mute Tab") { [weak self] in
            self?.toggleMute(id)
        })
        menu.addItem(ClosureMenuItem("Reload Tab") { [weak self] in
            self?.tabs.first { $0.id == id }?.browserView.reload()
        })
        menu.addItem(.separator())

        let groupItem = NSMenuItem(title: "Group", action: nil, keyEquivalent: "")
        let groupMenu = NSMenu()
        groupMenu.addItem(ClosureMenuItem("New Group with This Tab") { [weak self] in
            guard let self else { return }
            self.selectedIndex = index
            self.handleNewTabGroup()
        })
        for group in groups where group.id != tab.groupID {
            groupMenu.addItem(ClosureMenuItem(group.name) { [weak self] in
                guard let self else { return }
                self.selectedIndex = index
                self.addSelectedTabToGroup(group.id)
            })
        }
        if tab.groupID != nil {
            groupMenu.addItem(.separator())
            groupMenu.addItem(ClosureMenuItem("Remove from Group") { [weak self] in
                guard let self else { return }
                self.selectedIndex = index
                self.handleUngroupTab()
            })
        }
        groupItem.submenu = groupMenu
        menu.addItem(groupItem)
        menu.addItem(.separator())

        menu.addItem(ClosureMenuItem("Close Tab") { [weak self] in self?.closeTab(id: id) })
        menu.addItem(ClosureMenuItem("Close Other Tabs", enabled: tabs.count > 1) { [weak self] in
            self?.closeOtherTabs(id)
        })
        menu.addItem(ClosureMenuItem("Close Tabs to the Left", enabled: index > 0) { [weak self] in
            self?.closeTabsToTheLeft(id)
        })
        menu.addItem(ClosureMenuItem("Close Tabs to the Right", enabled: index + 1 < tabs.count) { [weak self] in
            self?.closeTabsToTheRight(id)
        })
        return menu
    }

    private func tabOverflowMenu() -> NSMenu? {
        guard !tabs.isEmpty else { return nil }
        let menu = NSMenu()
        for (index, tab) in tabs.enumerated() {
            let title = tab.displayTitle.count > 60
                ? String(tab.displayTitle.prefix(60)) + "…"
                : tab.displayTitle
            let icon = tab.favicon?.copy() as? NSImage
            icon?.size = NSSize(width: 14, height: 14)
            let item = ClosureMenuItem(title,
                                       state: index == selectedIndex ? .on : .off,
                                       image: icon) { [weak self] in
                self?.selectTab(id: tab.id)
            }
            menu.addItem(item)
        }
        return menu
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
        if statsVisible { positionStats() }
        tabStrip.update(with: tabs, groups: groups, selectedIndex: selectedIndex)
        sidebar.update(tabs: tabs, groups: groups, selectedIndex: selectedIndex)
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
        newTab(url: homeURL)
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
                PaletteCommand(id: "stats", title: "Toggle Stats for Nerds", subtitle: "Live page and engine diagnostics") { [weak self] in
                    self?.handleToggleStats()
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

            commands.append(PaletteCommand(id: "trays-reset", title: "Reset Shortcuts to Defaults",
                                           subtitle: "Restore the stock Developer, Personal and Entertainment trays") {
                Trays.reset()
            })
            commands.append(PaletteCommand(id: "group-new", title: "New Tab Group with This Tab",
                                           subtitle: "Start a group from the current tab") { [weak self] in
                self?.handleNewTabGroup()
            })
            for group in self.groups where group.id != self.selectedTab?.groupID {
                commands.append(PaletteCommand(id: "group-" + group.id.uuidString,
                                               title: "Move to Group: " + group.name,
                                               subtitle: "Add this tab to an existing group") { [weak self] in
                    self?.addSelectedTabToGroup(group.id)
                })
            }
            if self.selectedTab?.groupID != nil {
                commands.append(PaletteCommand(id: "group-remove", title: "Remove Tab from Group",
                                               subtitle: "Ungroup the current tab") { [weak self] in
                    self?.handleUngroupTab()
                })
                commands.append(PaletteCommand(id: "group-collapse", title: "Collapse or Expand Group",
                                               subtitle: "Fold this group in the tab strip") { [weak self] in
                    self?.handleToggleGroupCollapsed()
                })
                commands.append(PaletteCommand(id: "group-close", title: "Close Group",
                                               subtitle: "Close every tab in this group") { [weak self] in
                    self?.handleCloseGroup()
                })
            }

            if let tab = self.selectedTab, tab.url.hasPrefix("http") {
                for tray in Trays.all {
                    commands.append(PaletteCommand(id: "shortcut-" + tray.name,
                                                   title: "Add to Shortcuts: " + tray.name,
                                                   subtitle: "Pin this page to the " + tray.name + " tray") { [weak self] in
                        self?.addCurrentTabToTray(tray.name)
                    })
                }
            }

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
        case "addShortcut":
            Trays.addSite(title: payload["title"] as? String ?? "",
                          url: payload["url"] as? String ?? "",
                          tray: payload["tray"] as? String)
            pushState(force: true)
        case "removeShortcut":
            if let url = payload["url"] as? String {
                Trays.removeSite(url: url, tray: payload["tray"] as? String)
                pushState(force: true)
            }
        case "moveShortcut":
            if let url = payload["url"] as? String,
               let tray = payload["tray"] as? String,
               let index = payload["index"] as? Int {
                Trays.moveSite(url: url, tray: tray, to: index)
                pushState(force: true)
            }
        case "renameShortcut":
            if let url = payload["url"] as? String,
               let tray = payload["tray"] as? String,
               let title = payload["title"] as? String {
                Trays.renameSite(url: url, tray: tray, title: title)
                pushState(force: true)
            }
        case "resetTrays":
            Trays.reset()
            pushState(force: true)
        case "addTray":
            if let name = payload["name"] as? String {
                Trays.addTray(name: name)
                pushState(force: true)
            }
        case "removeTray":
            if let name = payload["name"] as? String {
                Trays.removeTray(name: name)
                pushState(force: true)
            }
        case "renameTray":
            if let from = payload["from"] as? String, let to = payload["to"] as? String {
                Trays.renameTray(from: from, to: to)
                pushState(force: true)
            }
        case "setDevServerScope":
            DevServerMonitor.shared.stop()
            DevServerMonitor.showAll = payload["all"] as? Bool ?? false
            DevServerMonitor.shared.start()
            pushState(force: true)
        case "setDevServerAutoReload":
            DevServerMonitor.autoReload = payload["enabled"] as? Bool ?? true
            pushState(force: true)
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

    private static let isoFormatter = ISO8601DateFormatter()

    private var historyRevision = -1
    private var historyPayload: [[String: Any]] = []
    private var bookmarkRevision = -1
    private var bookmarkPayload: [[String: Any]] = []
    private var trayRevision = -1
    private var trayPayload: [[String: Any]] = []
    private var lastSignature = ""
    private var stateRevision = 0

    private var hasInternalPage: Bool {
        tabs.contains { ForgeURL.isInternal($0.url) }
    }

    private func commitCounters() {
        StatsStore.shared.commitSessionCounters(blocked: FGAdblock.shared.blockedCount,
                                                bytes: FGAdblock.shared.estimatedBytesSaved)
    }

    private func refreshCachedPayloads() {
        if historyRevision != HistoryStore.shared.revision {
            historyRevision = HistoryStore.shared.revision
            historyPayload = HistoryStore.shared.recent(300).map {
                ["title": $0.title,
                 "url": $0.url,
                 "at": Self.isoFormatter.string(from: $0.visitedAt)]
            }
        }
        if bookmarkRevision != BookmarkStore.shared.revision {
            bookmarkRevision = BookmarkStore.shared.revision
            bookmarkPayload = BookmarkStore.shared.all.map { ["title": $0.title, "url": $0.url] }
        }
        if trayRevision != Trays.revision {
            trayRevision = Trays.revision
            trayPayload = Trays.all.map { tray in
                ["name": tray.name, "sites": tray.sites.map { ["title": $0.title, "url": $0.url] }]
            }
        }
    }

    private func pushState(force: Bool = false) {
        commitCounters()
        guard force || hasInternalPage else { return }

        refreshCachedPayloads()

        let store = FGStateStore.shared
        let servers = DevServerMonitor.shared.servers
        let downloads = FGDownloads.shared.snapshot()

        let signature = [
            String(historyRevision),
            String(bookmarkRevision),
            String(trayRevision),
            SearchEngines.current.id,
            orientation.rawValue,
            servers.map { String($0.port) }.joined(separator: ","),
            String(FGAdblock.shared.blockedCount),
            DevServerMonitor.showAll ? "all" : "dev",
            String(downloads.count),
            String(StatsStore.shared.lifetimeBlocked),
            String(FGAdblock.shared.blockedPopupCount)
        ].joined(separator: "|")

        if signature != lastSignature {
            lastSignature = signature
            stateRevision += 1
        } else if !force {
            return
        }

        store.setValue(SearchEngines.all.map { ["id": $0.id, "name": $0.name] }, forStateKey: "searchEngines")
        store.setValue(SearchEngines.current.id, forStateKey: "currentSearchEngine")
        store.setValue(trayPayload, forStateKey: "trays")
        store.setValue(servers.map {
            ["port": $0.port, "process": $0.processName, "url": $0.url]
        }, forStateKey: "devServers")
        store.setValue(DevTools.all.map { ["id": $0.id, "name": $0.name, "url": $0.url, "group": $0.group] }, forStateKey: "tools")
        store.setValue(DevServerMonitor.showAll, forStateKey: "devServersShowAll")
        store.setValue(DevServerMonitor.autoReload, forStateKey: "devServerAutoReload")

        let statsPayload: [String: Any] = [
            "lifetimeBlocked": StatsStore.shared.lifetimeBlocked,
            "lifetimeBytesSaved": StatsStore.shared.lifetimeBytesSaved,
            "estimatedSecondsSaved": StatsStore.estimatedSecondsSaved(
                fromBytes: StatsStore.shared.lifetimeBytesSaved,
                blockedRequests: StatsStore.shared.lifetimeBlocked
            )
        ]
        store.setValue(statsPayload, forStateKey: "stats")
        store.setValue(bookmarkPayload, forStateKey: "bookmarks")
        store.setValue(historyPayload, forStateKey: "history")
        store.setValue(orientation.rawValue, forStateKey: "tabOrientation")
        store.setValue(downloads, forStateKey: "downloads")
        store.setValue([
            "popupsBlocked": FGAdblock.shared.blockedPopupCount,
            "lists": FGAdblock.shared.listCount,
            "requestsSeen": FGAdblock.shared.requestsSeen,
            "sessionBlocked": FGAdblock.shared.blockedCount,
            "byType": FGAdblock.shared.blockedByType
        ], forStateKey: "shields")
        store.setValue(FGEngine.cefVersion(), forStateKey: "cefVersion")
        store.setValue(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
                       forStateKey: "version")
        store.setValue(stateRevision, forStateKey: "revision")
    }

    // MARK: - FGBrowserViewDelegate

    func browserView(_ view: FGBrowserView, didChangeURL url: String) {
        guard let tab = tabs.first(where: { $0.browserView === view }) else { return }
        tab.url = url
        if tab.favicon == nil, let cached = FaviconStore.shared.icon(for: url) {
            tab.favicon = cached
            tabStrip.update(with: tabs, groups: groups, selectedIndex: selectedIndex)
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
        tabStrip.update(with: tabs, groups: groups, selectedIndex: selectedIndex)
    }

    func browserView(_ view: FGBrowserView, didChangeTitle title: String) {
        guard let tab = tabs.first(where: { $0.browserView === view }) else { return }
        tab.title = title
        if !isPrivate { HistoryStore.shared.record(url: tab.url, title: title) }
        tabStrip.update(with: tabs, groups: groups, selectedIndex: selectedIndex)
        if tab === selectedTab { updateToolbarState() }
    }

    func browserView(_ view: FGBrowserView, didChangeLoading loading: Bool, canGoBack: Bool, canGoForward: Bool) {
        guard let tab = tabs.first(where: { $0.browserView === view }) else { return }
        tab.isLoading = loading
        tab.canGoBack = canGoBack
        tab.canGoForward = canGoForward
        tabStrip.update(with: tabs, groups: groups, selectedIndex: selectedIndex)
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
