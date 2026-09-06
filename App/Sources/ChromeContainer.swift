import AppKit

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
    var sidebarWidth: CGFloat = 0 {
        didSet {
            guard sidebarWidth != oldValue else { return }
            layoutSubtree(animated: true)
        }
    }

    var nowPlayingVisible = false {
        didSet {
            guard nowPlayingVisible != oldValue else { return }
            nowPlaying?.isHidden = !nowPlayingVisible
            layoutSubtree(animated: true)
        }
    }

    static let nowPlayingHeight: CGFloat = 52

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

        let toolbarHeight = Theme.Metrics.toolbarHeight
        let mediaHeight = nowPlayingVisible ? Self.nowPlayingHeight : 0
        let usableHeight = max(0, bounds.height - mediaHeight)
        var stripFrame = NSRect.zero
        var toolbarFrame = NSRect.zero
        var dividerFrame = NSRect.zero
        var contentFrame = NSRect.zero

        var sidebarFrame = NSRect.zero

        if orientation == .horizontal {
            let stripHeight: CGFloat = 42
            let top = stripHeight + toolbarHeight
            stripFrame = NSRect(x: 0, y: 0, width: bounds.width, height: stripHeight)
            toolbarFrame = NSRect(x: 0, y: stripHeight, width: bounds.width, height: toolbarHeight)
            dividerFrame = NSRect(x: 0, y: top - 1, width: bounds.width, height: 1)
            sidebarFrame = NSRect(x: 0, y: top, width: sidebarWidth,
                                  height: max(0, usableHeight - top))
            contentFrame = NSRect(x: sidebarWidth, y: top,
                                  width: max(0, bounds.width - sidebarWidth),
                                  height: max(0, usableHeight - top))
        } else {
            let stripWidth = Theme.Metrics.sidebarWidth
            toolbarFrame = NSRect(x: 0, y: 0, width: bounds.width, height: toolbarHeight)
            dividerFrame = NSRect(x: 0, y: toolbarHeight - 1, width: bounds.width, height: 1)
            sidebarFrame = NSRect(x: 0, y: toolbarHeight, width: sidebarWidth,
                                  height: max(0, usableHeight - toolbarHeight))
            stripFrame = NSRect(x: sidebarWidth, y: toolbarHeight, width: stripWidth,
                                height: max(0, usableHeight - toolbarHeight))
            contentFrame = NSRect(x: sidebarWidth + stripWidth, y: toolbarHeight,
                                  width: max(0, bounds.width - stripWidth - sidebarWidth),
                                  height: max(0, usableHeight - toolbarHeight))
        }

        let mediaFrame = NSRect(x: 0, y: usableHeight, width: bounds.width, height: mediaHeight)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.26
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.61, 0.36, 1)
                tabStrip.animator().frame = stripFrame
                toolbar.animator().frame = toolbarFrame
                divider.animator().frame = dividerFrame
                content.animator().frame = contentFrame
                nowPlaying?.animator().frame = mediaFrame
                sidebar?.animator().frame = sidebarFrame
            }
        } else {
            tabStrip.frame = stripFrame
            toolbar.frame = toolbarFrame
            divider.frame = dividerFrame
            content.frame = contentFrame
            nowPlaying?.frame = mediaFrame
            sidebar?.frame = sidebarFrame
        }
    }
}

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
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        applyStyle()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func applyStyle() {
        Theme.animate(0.22) {
            self.layer?.backgroundColor = Theme.panel.cgColor
            let accent = self.accentOverride ?? Theme.moss
            self.layer?.borderColor = (self.isFocused ? accent : Theme.line2).cgColor
            self.layer?.shadowColor = (self.accentOverride ?? Theme.acid).cgColor
            self.layer?.shadowOpacity = self.isFocused ? 0.18 : 0
            self.layer?.shadowRadius = 12
            self.layer?.shadowOffset = .zero
        }
    }
}


final class CallbackView: NSView {
    var onLayout: (() -> Void)?

    override func layout() {
        super.layout()
        onLayout?()
    }
}
