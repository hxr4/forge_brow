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
    private let securityIcon = NSImageView()
    private let sidebarButton = ChromeButton(symbol: "sidebar.left", label: "Toggle Sidebar (⌃⌘S)",
                                             pointSize: 14, target: nil, action: nil)
    private let backButton = ChromeButton(symbol: "chevron.left", label: "Back (⌘[)",
                                          pointSize: 14, weight: .medium, target: nil, action: nil)
    private let forwardButton = ChromeButton(symbol: "chevron.right", label: "Forward (⌘])",
                                             pointSize: 14, weight: .medium, target: nil, action: nil)
    private let reloadButton = ChromeButton(symbol: "arrow.clockwise", label: "Reload (⌘R)",
                                            pointSize: 13, weight: .medium, target: nil, action: nil)
    private let shieldsButton = ChromeButton(symbol: "shield.lefthalf.filled", label: "Shields",
                                             pointSize: 13, target: nil, action: nil)
    private let menuButton = ChromeButton(symbol: "ellipsis", label: "Forge Menu",
                                          pointSize: 14, weight: .semibold, target: nil, action: nil)
    private let bypassPill = NSTextField(labelWithString: "")
    private let privatePill = NSTextField(labelWithString: "")
    private let progressView = LoadProgressView()
    private let statusBubble = StatusBubble()
    private var fullscreenTabID: UUID?
    private var enteredWindowFullscreenForContent = false
    private var observers: [NSObjectProtocol] = []
    private var keyMonitor: Any?

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
            sidebar.hidesTabsSection = newValue == .vertical
            layoutToolbar()
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

    convenience init(isPrivate: Bool, openHome: Bool = true) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1360, height: 880),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Forge"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // An empty compact toolbar centres the traffic lights in a 38pt band, so
        // the tab strip can share the titlebar row instead of stacking under it.
        let shelf = NSToolbar(identifier: "ForgeTitlebar")
        shelf.showsBaselineSeparator = false
        shelf.allowsUserCustomization = false
        window.toolbar = shelf
        window.toolbarStyle = .unifiedCompact
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.minSize = NSSize(width: 560, height: 360)
        window.isReleasedWhenClosed = false
        window.backgroundColor = Theme.ink
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()
        window.setFrameAutosaveName("ForgeMainWindow")
        self.init(window: window)
        self.isPrivate = isPrivate
        window.title = isPrivate ? "Forge Private" : "Forge"
        buildInterface()
        configurePalette()
        startMonitors()
        observeWindow()
        if openHome { newTab(url: homeURL) }
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func observeWindow() {
        guard let window else { return }
        let center = NotificationCenter.default
        let measure: (Notification) -> Void = { [weak self] _ in self?.measureTitlebar() }
        observers.append(center.addObserver(forName: NSWindow.didResizeNotification, object: window,
                                            queue: .main, using: measure))
        observers.append(center.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window,
                                            queue: .main) { [weak self] _ in
            self?.chrome.isWindowFullscreen = true
            self?.layoutToolbar()
        })
        observers.append(center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window,
                                            queue: .main) { [weak self] _ in
            guard let self else { return }
            self.chrome.isWindowFullscreen = false
            self.enteredWindowFullscreenForContent = false
            self.measureTitlebar()
            self.layoutToolbar()
        })
        // Leaving macOS fullscreen (green button, ⌃⌘F, Esc) must also take the
        // page out of HTML5 fullscreen, or the player stays stretched.
        observers.append(center.addObserver(forName: NSWindow.willExitFullScreenNotification, object: window,
                                            queue: .main) { [weak self] _ in
            guard let self, let tab = self.fullscreenTab else { return }
            self.enteredWindowFullscreenForContent = false
            tab.browserView.exitContentFullscreen()
        })
        // v1 never released closed windows: their tabs kept playing audio in the
        // background and every closed window came back on the next launch.
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                            queue: .main) { [weak self] _ in self?.teardown() })
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window,
                                            queue: .main) { [weak self] _ in self?.tabStrip.alphaValue = 1 })
        observers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: window,
                                            queue: .main) { [weak self] _ in self?.tabStrip.alphaValue = 0.82 })
        // Esc leaves video fullscreen even when keyboard focus is not inside the page
        // (CEF only sees the key when its view is first responder).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53, event.window === self.window,
                  self.chrome.isImmersive, let tab = self.fullscreenTab else { return event }
            tab.browserView.exitContentFullscreen()
            return nil
        }
        measureTitlebar()
    }

    private func teardown() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        stateTimer?.invalidate()
        statsTimer?.invalidate()
        audioTimer?.invalidate()
        suggestionDebounce?.invalidate()
        stateTimer = nil
        if !isPrivate {
            for tab in tabs where tab.url.hasPrefix("http") {
                ClosedTabStore.shared.push(url: tab.url, title: tab.title)
            }
        }
        for tab in tabs {
            tab.browserView.closeBrowser()
            tab.browserView.removeFromSuperview()
        }
        tabs.removeAll()
        (NSApp.delegate as? ForgeAppDelegate)?.windowDidClose(self)
    }

    private func measureTitlebar() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        let band = window.frame.height - window.contentLayoutRect.height
        chrome.topRowHeight = max(Theme.Metrics.stripHeight, band.rounded())
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
        chrome.wantsLayer = true
        chrome.layer?.backgroundColor = Theme.ink.cgColor
        root.addSubview(chrome)

        tabStrip.onSelect = { [weak self] id in self?.selectTab(id: id) }
        tabStrip.onClose = { [weak self] id in self?.closeTab(id: id) }
        tabStrip.onNewTab = { [weak self] in self?.handleNewTab() }
        tabStrip.onToggleGroup = { [weak self] id in self?.toggleGroupCollapsed(id) }
        tabStrip.menuProvider = { [weak self] id in self?.tabContextMenu(for: id) }
        tabStrip.overflowMenuProvider = { [weak self] in self?.tabOverflowMenu() }
        tabStrip.onMove = { [weak self] moving, target in self?.moveTab(moving, to: target) }

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
        chrome.addSubview(progressView)
        progressView.color = isPrivate ? Theme.privateAccent : Theme.accent

        chrome.tabStrip = tabStrip
        chrome.toolbar = toolbarView
        chrome.content = contentContainer
        chrome.divider = dividerView
        chrome.progress = progressView
        chrome.sidebar = sidebar
        chrome.nowPlaying = nowPlayingBar
        buildSidebar()
        nowPlayingBar.isHidden = true
        buildNowPlaying()

        buildToolbar()
        buildFindBar()
        buildSuggestions()
        contentContainer.addSubview(statusBubble, positioned: .above, relativeTo: nil)
        orientation = orientation
    }

    private func buildToolbar() {
        let wire: [(ChromeButton, Selector)] = [
            (sidebarButton, #selector(handleToggleSidebar)),
            (backButton, #selector(handleBack)),
            (forwardButton, #selector(handleForward)),
            (reloadButton, #selector(handleReload)),
            (shieldsButton, #selector(handleShowShields)),
            (menuButton, #selector(handleShowForgeMenu))
        ]
        for (button, action) in wire {
            button.target = self
            button.action = action
        }
        sidebarButton.isToggled = sidebar.isOpen

        addressField.isBezeled = false
        addressField.drawsBackground = false
        addressField.focusRingType = .none
        addressField.font = .systemFont(ofSize: 13)
        addressField.textColor = Theme.cream
        addressField.delegate = self
        addressField.target = self
        addressField.action = #selector(handleAddressSubmit)
        addressField.cell?.lineBreakMode = .byTruncatingTail
        addressField.placeholderAttributedString = NSAttributedString(
            string: isPrivate ? "Search privately or enter address" : "Search or enter address",
            attributes: [.foregroundColor: Theme.muted, .font: NSFont.systemFont(ofSize: 13)]
        )
        addressField.translatesAutoresizingMaskIntoConstraints = false
        securityIcon.translatesAutoresizingMaskIntoConstraints = false
        securityIcon.imageScaling = .scaleNone
        addressBox.addSubview(securityIcon)
        addressBox.addSubview(addressField)
        NSLayoutConstraint.activate([
            securityIcon.leadingAnchor.constraint(equalTo: addressBox.leadingAnchor, constant: 9),
            securityIcon.centerYAnchor.constraint(equalTo: addressBox.centerYAnchor),
            securityIcon.widthAnchor.constraint(equalToConstant: 16),
            addressField.leadingAnchor.constraint(equalTo: securityIcon.trailingAnchor, constant: 5),
            addressField.trailingAnchor.constraint(equalTo: addressBox.trailingAnchor, constant: -10),
            addressField.centerYAnchor.constraint(equalTo: addressBox.centerYAnchor)
        ])
        if isPrivate {
            addressBox.accentOverride = Theme.privateAccent
        }

        for pill in [bypassPill, privatePill] {
            pill.font = .systemFont(ofSize: 11, weight: .semibold)
            pill.alignment = .center
            pill.wantsLayer = true
            pill.layer?.cornerRadius = 5
            pill.layer?.borderWidth = 1
        }
        bypassPill.textColor = Theme.warn
        bypassPill.layer?.backgroundColor = Theme.warn.withAlphaComponent(0.12).cgColor
        bypassPill.layer?.borderColor = Theme.warn.withAlphaComponent(0.5).cgColor
        bypassPill.toolTip = "Certificate errors are ignored in this tab. Tools ▸ Ignore Certificate Errors to turn off."
        bypassPill.isHidden = true

        privatePill.stringValue = "Private"
        privatePill.textColor = Theme.privateAccent
        privatePill.layer?.backgroundColor = Theme.privateAccent.withAlphaComponent(0.12).cgColor
        privatePill.layer?.borderColor = Theme.privateAccent.withAlphaComponent(0.45).cgColor
        privatePill.toolTip = "Nothing from this window is saved to history, cookies or the session."
        privatePill.isHidden = !isPrivate

        shieldsButton.imagePosition = .imageLeading
        shieldsButton.imageHugsTitle = true

        for view in [sidebarButton, backButton, forwardButton, reloadButton, addressBox, privatePill,
                     bypassPill, shieldsButton, menuButton] as [NSView] {
            toolbarView.addSubview(view)
        }
        toolbarView.wantsLayer = true
        toolbarView.layer?.backgroundColor = Theme.ink.cgColor
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
        sidebar.onToggleBlock = { [weak self] host in
            CustomRules.toggle(host)
            self?.refreshChrome()
        }
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
        sidebarButton.isToggled = sidebar.isOpen
    }

    @objc func handleShowNetworkInspector() {
        sidebar.show(.network)
        chrome.sidebarWidth = sidebar.preferredWidth
        sidebarButton.isToggled = true
    }

    @objc func handleShowShields() {
        guard let tab = selectedTab else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let here = tab.browserView.blockedCountForTab
        let hidden = tab.browserView.cosmeticSelectorCount
        let host = HiddenElements.host(of: tab.url) ?? "this page"

        let header = NSMenuItem(title: "Shields for \(host)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        func stat(_ text: String) {
            let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        stat("\(formatter.string(from: NSNumber(value: here)) ?? "0") requests blocked on this page")
        if hidden > 0 { stat("\(hidden) cosmetic rules active") }
        stat("\(formatter.string(from: NSNumber(value: FGAdblock.shared.blockedCount)) ?? "0") blocked this session")
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Network Inspector…") { [weak self] in self?.handleShowNetworkInspector() })
        if tab.url.hasPrefix("http"), HiddenElements.selectors(for: tab.url).count > 0 {
            menu.addItem(ClosureMenuItem("Restore Hidden Elements on \(host)") { [weak self] in
                self?.restoreHiddenElements(in: tab.browserView)
            })
        }
        menu.addItem(ClosureMenuItem("Stats for Nerds") { [weak self] in self?.handleToggleStats() })
        popUp(menu, under: shieldsButton)
    }

    @objc func handleShowForgeMenu() {
        let menu = NSMenu()
        func add(_ title: String, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command,
                 _ handler: @escaping () -> Void) {
            let item = ClosureMenuItem(title, handler: handler)
            item.keyEquivalent = key
            item.keyEquivalentModifierMask = mods
            menu.addItem(item)
        }
        add("New Tab", "t") { [weak self] in self?.handleNewTab() }
        add("New Window", "n") { (NSApp.delegate as? ForgeAppDelegate)?.openNewWindow() }
        add("New Private Window", "n", [.command, .shift]) { (NSApp.delegate as? ForgeAppDelegate)?.openPrivateWindow() }
        menu.addItem(.separator())
        add("Command Palette", "k") { [weak self] in self?.handleTogglePalette() }
        add("Find in Page…", "f") { [weak self] in self?.handleFind() }
        let zoom = selectedTab?.browserView.zoomPercent() ?? 100
        add("Zoom In (\(zoom)%)", "+") { [weak self] in self?.handleZoomIn() }
        add("Zoom Out", "-") { [weak self] in self?.handleZoomOut() }
        add("Actual Size", "0") { [weak self] in self?.handleActualSize() }
        menu.addItem(.separator())
        add(orientation == .horizontal ? "Use Vertical Tabs" : "Use Horizontal Tabs", "e", [.command, .shift]) {
            [weak self] in self?.handleToggleOrientation()
        }
        add(sidebar.isOpen ? "Hide Sidebar" : "Show Sidebar", "s", [.command, .control]) {
            [weak self] in self?.handleToggleSidebar()
        }
        menu.addItem(.separator())
        add("Bookmarks", "b", [.command, .option]) { [weak self] in self?.handleShowBookmarks() }
        add("History", "y") { [weak self] in self?.handleShowHistory() }
        add("Downloads", "j", [.command, .shift]) { [weak self] in self?.handleShowDownloads() }
        menu.addItem(.separator())
        add("Developer Tools", "i", [.command, .option]) { [weak self] in self?.handleShowDevTools() }
        add("Stats for Nerds", "s", [.command, .option]) { [weak self] in self?.handleToggleStats() }
        menu.addItem(.separator())
        add("Settings…", ",") { [weak self] in self?.handleShowSettings() }
        add("Help") { [weak self] in self?.handleShowHelp() }
        popUp(menu, under: menuButton)
    }

    private func popUp(_ menu: NSMenu, under button: NSView) {
        guard let window else { return }
        let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
        menu.popUp(positioning: nil, at: NSPoint(x: rect.minX, y: rect.minY - 4), in: nil)
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
            self?.sidebar.update(tabs: self?.tabs ?? [], groups: self?.groups ?? [],
                                 selectedIndex: self?.selectedIndex ?? 0)
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
        let h = toolbarView.bounds.height
        let size = Theme.Metrics.controlHeight
        let y = ((h - size) / 2).rounded()
        var x: CGFloat = 8

        for button in [sidebarButton, backButton, forwardButton, reloadButton] {
            button.frame = NSRect(x: x, y: y, width: 30, height: size)
            x += 32
        }
        x += 6

        var right = toolbarView.bounds.width - 8
        right -= 30
        menuButton.frame = NSRect(x: right, y: y, width: 30, height: size)
        right -= 4
        let shieldsWidth = max(30, shieldsButton.attributedTitle.size().width + 34)
        right -= shieldsWidth
        shieldsButton.frame = NSRect(x: right, y: y, width: shieldsWidth, height: size)
        right -= 8

        if !bypassPill.isHidden {
            right -= 148
            bypassPill.frame = NSRect(x: right, y: y + 5, width: 148, height: 18)
            right -= 8
        }
        if !privatePill.isHidden {
            right -= 62
            privatePill.frame = NSRect(x: right, y: y + 5, width: 62, height: 18)
            right -= 8
        }

        // Keep the address well visually centred in the window when there is room.
        let available = max(140, right - x)
        let ideal = min(available, 760)
        var fieldX = x
        if let window, available > ideal {
            let windowMid = window.frame.width / 2
            let localMid = toolbarView.convert(NSPoint(x: windowMid, y: 0), from: chrome).x
            fieldX = min(max(x, localMid - ideal / 2), right - ideal)
        }
        addressBox.frame = NSRect(x: fieldX, y: y, width: ideal, height: size)
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
            self?.sidebar.update(tabs: self?.tabs ?? [], groups: self?.groups ?? [],
                                 selectedIndex: self?.selectedIndex ?? 0)
        }
        RunLoop.main.add(timer, forMode: .common)
        stateTimer = timer
        pushState(force: true)
    }

    // MARK: - Tabs

    var isRestorable: Bool { !isPrivate }

    func sessionWindow() -> SessionWindow? {
        guard !isPrivate else { return nil }
        let entries: [SessionTab] = tabs.compactMap { tab in
            let target = tab.url.isEmpty ? homeURL : tab.url
            guard target.hasPrefix("http://") || target.hasPrefix("https://") || target == homeURL else {
                return nil
            }
            return SessionTab(url: target, title: tab.title, groupID: tab.groupID?.uuidString)
        }
        guard !entries.isEmpty else { return nil }
        let stored = groups.map {
            SessionGroup(id: $0.id.uuidString, name: $0.name,
                         colorIndex: $0.colorIndex, isCollapsed: $0.isCollapsed)
        }
        let box = window?.frame ?? .zero
        return SessionWindow(
            frame: [box.origin.x, box.origin.y, box.size.width, box.size.height],
            tabs: entries,
            groups: stored,
            selectedIndex: min(max(0, selectedIndex), max(0, entries.count - 1)))
    }

    func restore(_ saved: SessionWindow) {
        guard !isPrivate else { return }

        var remapped: [String: UUID] = [:]
        groups = saved.groups.map { stored in
            var group = TabGroup(name: stored.name, colorIndex: stored.colorIndex)
            group.isCollapsed = stored.isCollapsed
            remapped[stored.id] = group.id
            return group
        }

        for tab in tabs {
            tab.browserView.closeBrowser()
            tab.browserView.removeFromSuperview()
        }
        tabs.removeAll()

        for entry in saved.tabs {
            let tab = Tab(restoring: entry, isPrivate: false)
            if let raw = entry.groupID { tab.groupID = remapped[raw] }
            tabs.append(tab)
        }

        if tabs.isEmpty { newTab(url: homeURL); return }

        selectedIndex = min(max(0, saved.selectedIndex), tabs.count - 1)
        if saved.frame.count == 4 {
            let box = NSRect(x: saved.frame[0], y: saved.frame[1],
                             width: saved.frame[2], height: saved.frame[3])
            if box.width > 400, box.height > 300, NSScreen.screens.contains(where: { $0.frame.intersects(box) }) {
                window?.setFrame(box, display: false)
            }
        }
        refreshChrome()
    }

    func scheduleSessionSave() {
        guard !isPrivate else { return }
        (NSApp.delegate as? ForgeAppDelegate)?.scheduleSessionSave()
    }

    /// Tabs opened from a page land beside their opener (after any siblings it
    /// already opened), not at the far end of the strip.
    private var openerChildren: (opener: UUID, last: UUID)?

    @discardableResult
    func newTab(url: String, select: Bool = true, fromOpener opener: Tab? = nil) -> Tab {
        let tab = Tab(url: url, isPrivate: isPrivate)
        var index = tabs.count
        if let opener, let openerIndex = tabIndex(opener.id) {
            index = openerIndex + 1
            if let chain = openerChildren, chain.opener == opener.id, let last = tabIndex(chain.last) {
                index = last + 1
            }
            tab.groupID = opener.groupID
            openerChildren = (opener.id, tab.id)
        } else {
            openerChildren = nil
        }
        tabs.insert(tab, at: index)
        attach(tab)

        if select {
            selectedIndex = index
        } else if index <= selectedIndex {
            selectedIndex += 1
        }
        refreshChrome()
        scheduleSessionSave()
        return tab
    }

    func moveTab(_ id: UUID, to targetID: UUID) {
        guard let from = tabIndex(id), let to = tabIndex(targetID), from != to else { return }
        let selectedID = selectedTab?.id
        let moving = tabs.remove(at: from)
        moving.groupID = tabs[min(to, tabs.count - 1)].groupID
        tabs.insert(moving, at: to)
        if let selectedID, let index = tabIndex(selectedID) { selectedIndex = index }
        openerChildren = nil
        pruneGroups()
        tabStrip.update(with: tabs, groups: groups, selectedIndex: selectedIndex)
        sidebar.update(tabs: tabs, groups: groups, selectedIndex: selectedIndex)
        scheduleSessionSave()
    }

    /// ⌘1…⌘8 pick that tab, ⌘9 always picks the last one.
    func selectTab(number: Int) {
        guard !tabs.isEmpty else { return }
        selectedIndex = number >= 9 ? tabs.count - 1 : min(number - 1, tabs.count - 1)
        refreshChrome()
    }

    private func attach(_ tab: Tab) {
        guard tab.browserView.superview == nil else { return }
        tab.browserView.browserDelegate = self
        tab.browserView.translatesAutoresizingMaskIntoConstraints = true
        tab.browserView.autoresizingMask = [.width, .height]
        tab.browserView.frame = contentContainer.bounds
        tab.browserView.isHidden = true
        contentContainer.addSubview(tab.browserView, positioned: .below, relativeTo: findBar)
        tab.wake()
    }

    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        closeTab(at: index)
    }

    func closeTab(at index: Int) {
        guard index >= 0, index < tabs.count else { return }
        let tab = tabs.remove(at: index)
        if !isPrivate { ClosedTabStore.shared.push(url: tab.url, title: tab.title) }
        tab.browserView.closeBrowser()
        tab.browserView.removeFromSuperview()
        scheduleSessionSave()

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

    private var fullscreenTab: Tab? {
        guard let id = fullscreenTabID else { return nil }
        return tabs.first { $0.id == id }
    }

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
        newTab(url: tab.url, fromOpener: tab)
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
        if let tab = selectedTab, tab.isDormant { attach(tab) }
        if let id = fullscreenTabID, selectedTab?.id != id {
            tabs.first { $0.id == id }?.browserView.exitContentFullscreen()
        }
        for (index, tab) in tabs.enumerated() {
            guard tab.browserView.superview != nil else { continue }
            tab.browserView.isHidden = index != selectedIndex
            if index == selectedIndex { tab.browserView.frame = contentContainer.bounds }
        }
        if findVisible { positionFindBar() }
        if statsVisible { positionStats() }
        statusBubble.isHidden = true
        progressView.set(progress: selectedTab?.isLoading == true ? 0.3 : 1, loading: selectedTab?.isLoading == true)
        tabStrip.update(with: tabs, groups: groups, selectedIndex: selectedIndex)
        sidebar.update(tabs: tabs, groups: groups, selectedIndex: selectedIndex)
        updateToolbarState()
    }

    private static let symbolCache = NSCache<NSString, NSImage>()

    private func symbol(_ name: String, size: CGFloat = 11, weight: NSFont.Weight = .semibold) -> NSImage? {
        let key = "\(name)-\(size)-\(weight.rawValue)" as NSString
        if let cached = Self.symbolCache.object(forKey: key) { return cached }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: weight))
        if let image { Self.symbolCache.setObject(image, forKey: key) }
        return image
    }

    /// Host in primary text, scheme and path receded, so the part that matters
    /// for trust (the domain) is the part you read first.
    private func addressDisplay(for url: String) -> NSAttributedString {
        let shown = ForgeURL.display(for: url)
        let font = NSFont.systemFont(ofSize: 13)
        let text = NSMutableAttributedString(string: shown, attributes: [.foregroundColor: Theme.bone, .font: font])
        if let host = URL(string: shown)?.host, let range = shown.range(of: host) {
            text.addAttribute(.foregroundColor, value: Theme.cream, range: NSRange(range, in: shown))
        } else {
            text.addAttribute(.foregroundColor, value: Theme.cream, range: NSRange(location: 0, length: text.length))
        }
        return text
    }

    private func updateToolbarState() {
        guard let tab = selectedTab else { return }
        let editing = window?.firstResponder === addressField.currentEditor() && addressField.currentEditor() != nil
        if !editing {
            let display = addressDisplay(for: tab.url)
            if addressField.attributedStringValue != display { addressField.attributedStringValue = display }
        }

        let iconName: String
        let iconTint: NSColor
        let iconTip: String
        if tab.ignoresCertificateErrors {
            (iconName, iconTint, iconTip) = ("exclamationmark.triangle.fill", Theme.warn, "Certificate checks are off for this tab")
        } else if tab.url.hasPrefix("https://") {
            (iconName, iconTint, iconTip) = ("lock.fill", Theme.muted, "Secure connection")
        } else if tab.url.hasPrefix("http://") {
            let local = ["localhost", "127.0.0.1", "[::1]"].contains { tab.url.contains("//" + $0) }
            (iconName, iconTint, iconTip) = local
                ? ("hammer.fill", Theme.muted, "Local development server")
                : ("lock.open.fill", Theme.warn, "Not secure: this page is not encrypted")
        } else {
            (iconName, iconTint, iconTip) = ("magnifyingglass", Theme.muted, "")
        }
        securityIcon.image = symbol(iconName)
        securityIcon.contentTintColor = iconTint
        securityIcon.toolTip = iconTip.isEmpty ? nil : iconTip

        backButton.isEnabled = tab.canGoBack
        forwardButton.isEnabled = tab.canGoForward
        reloadButton.setSymbol(tab.isLoading ? "xmark" : "arrow.clockwise",
                               label: tab.isLoading ? "Stop" : "Reload",
                               pointSize: 13, weight: .medium)
        reloadButton.toolTip = tab.isLoading ? "Stop (⌘.)" : "Reload (⌘R)"
        window?.title = tab.displayTitle.isEmpty ? "Forge" : tab.displayTitle

        let wasHidden = bypassPill.isHidden
        if tab.ignoresCertificateErrors {
            bypassPill.stringValue = "Cert checks off"
            bypassPill.isHidden = false
        } else {
            bypassPill.isHidden = true
        }
        if wasHidden != bypassPill.isHidden { layoutToolbar() }
        updateBlockCounter()
    }

    /// The shield shows what was blocked on *this* page; the lifetime number
    /// lives on the landing page where it is not competing with the URL.
    private func updateBlockCounter() {
        let count = selectedTab?.browserView.blockedCountForTab ?? 0
        let text = count == 0 ? "" : (count > 999 ? "999+" : String(count))
        guard shieldsButton.title != text else { return }
        shieldsButton.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: Theme.bone
        ])
        shieldsButton.imagePosition = text.isEmpty ? .imageOnly : .imageLeading
        shieldsButton.toolTip = count == 0 ? "Shields: nothing blocked on this page"
                                           : "Shields: \(count) requests blocked on this page"
        layoutToolbar()
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

    @objc func handleFocusAddress() {
        if chrome.isImmersive { selectedTab?.browserView.exitContentFullscreen() }
        window?.makeFirstResponder(addressField)
        addressField.currentEditor()?.selectAll(nil)
    }

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
        navigate(to: resolved)
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

    func navigate(to url: String) {
        guard let tab = selectedTab else { return }
        tab.browserView.loadURL(url)
        // Show where we are going right away; didChangeURL corrects redirects.
        tab.url = url
        updateToolbarState()
    }

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
            if let url = payload["url"] as? String {
                let background = payload["background"] as? Bool ?? false
                newTab(url: AddressResolver.resolve(url), select: !background, fromOpener: selectedTab)
            }
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
    private var lastCounters = ""
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

        // `revision` tells pages their *layout* changed (trays, servers, engines…).
        // Ad-block counters tick constantly on busy sites; they used to be part of
        // this signature, which made the landing page tear down and rebuild every
        // shortcut tile every 1.5s and swallowed clicks mid-press.
        let signature = [
            String(historyRevision),
            String(bookmarkRevision),
            String(trayRevision),
            SearchEngines.current.id,
            orientation.rawValue,
            servers.map { String($0.port) }.joined(separator: ","),
            DevServerMonitor.showAll ? "all" : "dev",
            String(downloads.count)
        ].joined(separator: "|")
        let counters = [
            String(FGAdblock.shared.blockedCount),
            String(StatsStore.shared.lifetimeBlocked),
            String(FGAdblock.shared.blockedPopupCount),
            downloads.map { String(describing: $0["percent"] ?? "") }.joined(separator: ",")
        ].joined(separator: "|")

        let layoutChanged = signature != lastSignature
        if layoutChanged {
            lastSignature = signature
            stateRevision += 1
        }
        if !layoutChanged && counters == lastCounters && !force {
            return
        }
        lastCounters = counters

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
        scheduleSessionSave()
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
        scheduleSessionSave()
    }

    func browserView(_ view: FGBrowserView, didChangeLoading loading: Bool, canGoBack: Bool, canGoForward: Bool) {
        guard let tab = tabs.first(where: { $0.browserView === view }) else { return }
        let finished = tab.isLoading && !loading
        tab.isLoading = loading
        tab.canGoBack = canGoBack
        tab.canGoForward = canGoForward
        if tab === selectedTab { progressView.set(progress: loading ? 0.1 : 1, loading: loading) }
        if finished, tab.url.hasPrefix("http"), !HiddenElements.selectors(for: tab.url).isEmpty {
            view.executeJavaScript(HiddenElements.injectionScript(for: tab.url))
        }
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
        let opener = tabs.first { $0.browserView === view }
        switch disposition {
        case .newWindow:
            open(url, in: .newWindow)
        case .newPrivateWindow:
            open(url, in: .privateWindow)
        default:
            newTab(url: url, select: disposition != .newBackgroundTab, fromOpener: opener)
        }
    }

    func browserView(_ view: FGBrowserView, requestsContextMenuWithParams params: [String: Any]) {
        guard let tab = tabs.first(where: { $0.browserView === view }), tab === selectedTab,
              let window else { return }
        // CEF's x/y are device pixels on Retina in recent Chromium; the real mouse
        // position in view points (top-left origin) is what the DOM and DevTools want.
        var params = params
        let mouse = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if view.bounds.contains(mouse) {
            params["x"] = mouse.x
            params["y"] = view.isFlipped ? mouse.y : view.bounds.height - mouse.y
        }
        let present: ([String: Any]?) -> Void = { [weak self] video in
            guard let self, let window = self.window else { return }
            let menu = PageContextMenu.build(for: params, tab: tab, host: self, overlaidVideo: video)
            let point = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            menu.popUp(positioning: nil, at: point, in: view)
        }
        let mediaType = (params["mediaType"] as? NSNumber)?.intValue ?? 0
        let page = params["pageURL"] as? String ?? ""
        guard mediaType == 0, page.hasPrefix("http") else { present(nil); return }
        let css = PageContextMenu.cssPointForProbe(params, in: view)
        view.evaluate(PageContextMenu.videoProbeScript(at: css)) { result in
            present(result as? [String: Any])
        }
    }

    func browserView(_ view: FGBrowserView, didChangeContentFullscreen fullscreen: Bool) {
        guard let tab = tabs.first(where: { $0.browserView === view }), let window else { return }
        if fullscreen {
            fullscreenTabID = tab.id
            if tab !== selectedTab { selectTab(id: tab.id) }
            hideFindBar()
            suggestionsView.dismiss()
            statusBubble.isHidden = true
            chrome.isImmersive = true
            if !window.styleMask.contains(.fullScreen) {
                enteredWindowFullscreenForContent = true
                window.toggleFullScreen(nil)
            }
        } else {
            guard fullscreenTabID == tab.id else { return }
            fullscreenTabID = nil
            chrome.isImmersive = false
            if enteredWindowFullscreenForContent, window.styleMask.contains(.fullScreen) {
                enteredWindowFullscreenForContent = false
                window.toggleFullScreen(nil)
            }
            refreshChrome()
        }
    }

    func browserView(_ view: FGBrowserView, didChangeLoadProgress progress: Double) {
        guard view === selectedTab?.browserView else { return }
        progressView.set(progress: progress, loading: view.isLoading)
    }

    func browserView(_ view: FGBrowserView, didChangeStatusText text: String) {
        guard view === selectedTab?.browserView, !chrome.isImmersive else { return }
        statusBubble.show(ForgeURL.display(for: text), in: contentContainer)
    }
}

// MARK: - Page context menu

extension BrowserWindowController: PageContextMenuHost {

    var isPrivateWindow: Bool { isPrivate }

    func open(_ url: String, in destination: LinkDestination) {
        switch destination {
        case .foregroundTab:
            newTab(url: url, select: true, fromOpener: selectedTab)
        case .backgroundTab:
            newTab(url: url, select: false, fromOpener: selectedTab)
        case .newWindow:
            (NSApp.delegate as? ForgeAppDelegate)?.openWindow(with: url, isPrivate: isPrivate)
        case .privateWindow:
            (NSApp.delegate as? ForgeAppDelegate)?.presentPrivateWindow(with: url)
        }
    }

    func searchWeb(for text: String, background: Bool) {
        newTab(url: SearchEngines.current.url(for: text), select: !background, fromOpener: selectedTab)
    }

    func toggleBookmark(url: String, title: String) {
        BookmarkStore.shared.toggle(title: title.isEmpty ? url : title, url: url)
        pushState(force: true)
    }

    func isBookmarked(url: String) -> Bool {
        BookmarkStore.shared.all.contains { $0.url == url }
    }

    func addShortcut(url: String, title: String, tray: String?) {
        Trays.addSite(title: title, url: url, tray: tray)
        pushState(force: true)
    }

    func hideElement(in view: FGBrowserView, atCSS point: NSPoint) {
        guard let tab = tabs.first(where: { $0.browserView === view }) else { return }
        let page = tab.url
        view.evaluate(HiddenElements.pickScript(at: point.x, point.y)) { result in
            guard let selector = result as? String, !selector.isEmpty else { NSSound.beep(); return }
            HiddenElements.add(selector, for: page)
        }
    }

    func restoreHiddenElements(in view: FGBrowserView) {
        guard let tab = tabs.first(where: { $0.browserView === view }) else { return }
        HiddenElements.clear(for: tab.url)
        view.reload()
    }

    func hasHiddenElements(for url: String) -> Bool {
        !HiddenElements.selectors(for: url).isEmpty
    }
}
