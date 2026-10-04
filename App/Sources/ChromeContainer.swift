import AppKit

/// Lays out the browser chrome. v2 folds the tab strip into the titlebar row
/// (beside the traffic lights) so horizontal mode costs 78pt of height instead
/// of 116pt, and vertical mode costs a single 40pt row.
final class ChromeContainer: NSView {

    var orientation: TabOrientation = .horizontal {
        didSet {
            guard orientation != oldValue else { return }
            layoutSubtree(animated: true)
        }
    }

    var tabStrip: NSView?
    var toolbar: NSView?
    var content: NSView?
    var divider: NSView?
    var nowPlaying: NSView?
    var sidebar: NSView?
    var progress: NSView?

    var sidebarWidth: CGFloat = 0 {
        didSet {
            guard sidebarWidth != oldValue else { return }
            layoutSubtree(animated: true)
        }
    }

    var nowPlayingVisible = false {
        didSet {
            guard nowPlayingVisible != oldValue else { return }
            nowPlaying?.isHidden = !nowPlayingVisible || isImmersive
            layoutSubtree(animated: true)
        }
    }

    /// Page-requested fullscreen (a video player): only the web content is shown.
    var isImmersive = false {
        didSet {
            guard isImmersive != oldValue else { return }
            for view in [tabStrip, toolbar, divider, sidebar, progress] { view?.isHidden = isImmersive }
            nowPlaying?.isHidden = isImmersive || !nowPlayingVisible
            layoutSubtree(animated: false)
        }
    }

    /// The window is in macOS fullscreen, so there are no traffic lights to clear.
    var isWindowFullscreen = false {
        didSet {
            guard isWindowFullscreen != oldValue else { return }
            layoutSubtree(animated: false)
        }
    }

    /// Leading space the first row reserves for the traffic lights.
    var leadingInset: CGFloat { isWindowFullscreen ? 8 : Theme.Metrics.trafficLightInset }

    var topRowHeight: CGFloat = Theme.Metrics.stripHeight {
        didSet { if topRowHeight != oldValue { layoutSubtree(animated: false) } }
    }

    static let nowPlayingHeight: CGFloat = 48

    override var isFlipped: Bool { true }

    private var isLayingOut = false

    override func layout() {
        super.layout()
        layoutSubtree(animated: false)
    }

    private func layoutSubtree(animated: Bool) {
        guard !isLayingOut else { return }
        guard let tabStrip, let toolbar, let content, let divider else { return }
        isLayingOut = true
        defer { isLayingOut = false }

        if isImmersive {
            content.frame = bounds
            return
        }

        let mediaHeight = nowPlayingVisible ? Self.nowPlayingHeight : 0
        let usableHeight = max(0, bounds.height - mediaHeight)
        var stripFrame = NSRect.zero
        var toolbarFrame = NSRect.zero
        var contentFrame = NSRect.zero
        var sidebarFrame = NSRect.zero
        let chromeBottom: CGFloat

        if orientation == .horizontal {
            let stripHeight = topRowHeight
            let toolbarHeight = Theme.Metrics.toolbarHeight
            chromeBottom = stripHeight + toolbarHeight
            stripFrame = NSRect(x: leadingInset, y: 0,
                                width: max(0, bounds.width - leadingInset), height: stripHeight)
            toolbarFrame = NSRect(x: 0, y: stripHeight, width: bounds.width, height: toolbarHeight)
            sidebarFrame = NSRect(x: 0, y: chromeBottom, width: sidebarWidth,
                                  height: max(0, usableHeight - chromeBottom))
            contentFrame = NSRect(x: sidebarWidth, y: chromeBottom,
                                  width: max(0, bounds.width - sidebarWidth),
                                  height: max(0, usableHeight - chromeBottom))
        } else {
            let toolbarHeight = max(topRowHeight, Theme.Metrics.toolbarHeight)
            let column = Theme.Metrics.sidebarWidth
            chromeBottom = toolbarHeight
            toolbarFrame = NSRect(x: leadingInset, y: 0,
                                  width: max(0, bounds.width - leadingInset), height: toolbarHeight)
            stripFrame = NSRect(x: 0, y: toolbarHeight, width: column,
                                height: max(0, usableHeight - toolbarHeight))
            sidebarFrame = NSRect(x: column, y: toolbarHeight, width: sidebarWidth,
                                  height: max(0, usableHeight - toolbarHeight))
            contentFrame = NSRect(x: column + sidebarWidth, y: toolbarHeight,
                                  width: max(0, bounds.width - column - sidebarWidth),
                                  height: max(0, usableHeight - toolbarHeight))
        }

        let dividerFrame = NSRect(x: orientation == .horizontal ? 0 : Theme.Metrics.sidebarWidth,
                                  y: chromeBottom - 1,
                                  width: bounds.width, height: 1)
        let progressFrame = NSRect(x: 0, y: chromeBottom - 2, width: bounds.width, height: 2)
        let mediaFrame = NSRect(x: 0, y: usableHeight, width: bounds.width, height: mediaHeight)

        let apply = {
            if animated {
                tabStrip.animator().frame = stripFrame
                toolbar.animator().frame = toolbarFrame
                divider.animator().frame = dividerFrame
                content.animator().frame = contentFrame
                self.nowPlaying?.animator().frame = mediaFrame
                self.sidebar?.animator().frame = sidebarFrame
            } else {
                tabStrip.frame = stripFrame
                toolbar.frame = toolbarFrame
                divider.frame = dividerFrame
                content.frame = contentFrame
                self.nowPlaying?.frame = mediaFrame
                self.sidebar?.frame = sidebarFrame
            }
            self.progress?.frame = progressFrame
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                apply()
            }
        } else {
            apply()
        }
    }
}

/// The address field's rounded well. Focus is a 1pt accent ring, no glow.
final class AddressFieldContainer: NSView {
    var isFocused = false {
        didSet { applyStyle() }
    }

    var accentOverride: NSColor? {
        didSet { applyStyle() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        applyStyle()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func applyStyle() {
        layer?.backgroundColor = (isFocused ? Theme.void : Theme.panel).cgColor
        let accent = accentOverride ?? Theme.accent
        layer?.borderColor = (isFocused ? accent.withAlphaComponent(0.8)
                                        : (accentOverride?.withAlphaComponent(0.45) ?? NSColor.clear)).cgColor
    }
}

/// Thin page-load progress line along the bottom edge of the chrome.
final class LoadProgressView: NSView {
    private let bar = NSView()
    private var hideWork: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        bar.wantsLayer = true
        bar.layer?.backgroundColor = Theme.accent.cgColor
        addSubview(bar)
        alphaValue = 0
    }

    required init?(coder: NSCoder) { fatalError() }

    var color: NSColor = Theme.accent {
        didSet { bar.layer?.backgroundColor = color.cgColor }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func set(progress: Double, loading: Bool) {
        hideWork?.cancel()
        let clamped = CGFloat(max(0.08, min(1, progress)))
        if loading && progress < 1 {
            if alphaValue == 0 { bar.frame = NSRect(x: 0, y: 0, width: 0, height: bounds.height) }
            alphaValue = 1
            Theme.animate(0.25) { bar.animator().frame = NSRect(x: 0, y: 0, width: bounds.width * clamped, height: bounds.height) }
        } else {
            guard alphaValue > 0 else { return }
            Theme.animate(0.18) { bar.animator().frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height) }
            let work = DispatchWorkItem { [weak self] in
                Theme.animate(0.25) { self?.animator().alphaValue = 0 }
            }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        }
    }

    func reset() {
        hideWork?.cancel()
        alphaValue = 0
        bar.frame = NSRect(x: 0, y: 0, width: 0, height: bounds.height)
    }
}

/// Hovered-link URL readout in the bottom-left corner of the page.
final class StatusBubble: NSView {
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.ink.withAlphaComponent(0.96).cgColor
        layer?.borderColor = Theme.line2.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 6
        label.font = .systemFont(ofSize: 11.5)
        label.textColor = Theme.bone
        label.lineBreakMode = .byTruncatingMiddle
        addSubview(label)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ text: String, in container: NSView) {
        guard !text.isEmpty else { isHidden = true; return }
        label.stringValue = text
        let maxWidth = min(container.bounds.width * 0.6, 640)
        let width = min(maxWidth, label.intrinsicContentSize.width + 18)
        frame = NSRect(x: 8, y: 8, width: width, height: 22)
        label.frame = NSRect(x: 9, y: 3, width: width - 18, height: 16)
        isHidden = false
    }
}

final class CallbackView: NSView {
    var onLayout: (() -> Void)?

    override func layout() {
        super.layout()
        onLayout?()
    }

    // Empty chrome drags the window, and double-click zooms it like a titlebar.
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if event.clickCount == 2 { window.performZoom(nil) } else { window.performDrag(with: event) }
    }
}
