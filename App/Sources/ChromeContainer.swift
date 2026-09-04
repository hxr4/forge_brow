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
        var stripFrame = NSRect.zero
        var toolbarFrame = NSRect.zero
        var dividerFrame = NSRect.zero
        var contentFrame = NSRect.zero

        if orientation == .horizontal {
            let stripHeight: CGFloat = 42
            stripFrame = NSRect(x: 0, y: 0, width: bounds.width, height: stripHeight)
            toolbarFrame = NSRect(x: 0, y: stripHeight, width: bounds.width, height: toolbarHeight)
            dividerFrame = NSRect(x: 0, y: stripHeight + toolbarHeight - 1, width: bounds.width, height: 1)
            contentFrame = NSRect(x: 0, y: stripHeight + toolbarHeight,
                                  width: bounds.width,
                                  height: max(0, bounds.height - stripHeight - toolbarHeight))
        } else {
            let sidebar = Theme.Metrics.sidebarWidth
            toolbarFrame = NSRect(x: 0, y: 0, width: bounds.width, height: toolbarHeight)
            dividerFrame = NSRect(x: 0, y: toolbarHeight - 1, width: bounds.width, height: 1)
            stripFrame = NSRect(x: 0, y: toolbarHeight, width: sidebar,
                                height: max(0, bounds.height - toolbarHeight))
            contentFrame = NSRect(x: sidebar, y: toolbarHeight,
                                  width: max(0, bounds.width - sidebar),
                                  height: max(0, bounds.height - toolbarHeight))
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.26
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.61, 0.36, 1)
                tabStrip.animator().frame = stripFrame
                toolbar.animator().frame = toolbarFrame
                divider.animator().frame = dividerFrame
                content.animator().frame = contentFrame
            }
        } else {
            tabStrip.frame = stripFrame
            toolbar.frame = toolbarFrame
            divider.frame = dividerFrame
            content.frame = contentFrame
        }
    }
}

final class AddressFieldContainer: NSView {
    var isFocused = false {
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
            self.layer?.borderColor = (self.isFocused ? Theme.moss : Theme.line2).cgColor
            self.layer?.shadowColor = Theme.acid.cgColor
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
