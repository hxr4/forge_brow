import AppKit

final class TabItemView: NSView {

    let tabID: UUID

    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?
    var onDragBegan: (() -> Void)?
    var onDragMoved: ((NSEvent) -> Void)?
    var onDragEnded: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private let spinner = NSProgressIndicator()
    private let closeButton = ChromeButton(symbol: "xmark", label: "Close Tab", pointSize: 9,
                                           weight: .semibold, target: nil, action: nil)
    private let groupBar = NSView()
    private let muteBadge = NSImageView()
    private var groupColor: NSColor?
    private var trackingArea: NSTrackingArea?

    private var isActive = false
    private var isHovering = false
    private var hasBypass = false
    private var isBusy = false
    private var hasFavicon = false

    private var dragOrigin: NSPoint?
    private(set) var isDragging = false

    private static let globe = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
    private static let warning = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                         accessibilityDescription: "Certificate checks off")?
        .withSymbolConfiguration(.init(pointSize: 10, weight: .regular))

    init(tabID: UUID) {
        self.tabID = tabID
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Theme.Metrics.tabRadius
        layer?.borderWidth = 0

        groupBar.wantsLayer = true
        groupBar.layer?.cornerRadius = 1
        groupBar.isHidden = true
        addSubview(groupBar)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 3
        addSubview(iconView)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.appearance = NSAppearance(named: .darkAqua)
        addSubview(spinner)

        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textColor = Theme.bone
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.cell?.truncatesLastVisibleLine = true
        addSubview(titleLabel)

        muteBadge.image = NSImage(systemSymbolName: "speaker.slash.fill", accessibilityDescription: "Muted")?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .regular))
        muteBadge.contentTintColor = Theme.bone
        muteBadge.isHidden = true
        addSubview(muteBadge)

        closeButton.target = self
        closeButton.action = #selector(handleClose)
        closeButton.layer?.cornerRadius = 4
        closeButton.tint = Theme.bone
        closeButton.alphaValue = 0
        addSubview(closeButton)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let h = bounds.height
        groupBar.frame = NSRect(x: 0, y: 7, width: 2, height: max(0, h - 14))
        let icon = NSRect(x: 9, y: (h - 16) / 2, width: 16, height: 16)
        iconView.frame = icon
        spinner.frame = icon
        closeButton.frame = NSRect(x: bounds.width - 22, y: (h - 16) / 2, width: 16, height: 16)
        var trailing = bounds.width - 26
        if !muteBadge.isHidden {
            muteBadge.frame = NSRect(x: trailing - 13, y: (h - 12) / 2, width: 13, height: 12)
            trailing -= 17
        }
        titleLabel.frame = NSRect(x: 32, y: (h - 16) / 2, width: max(0, trailing - 32), height: 16)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        applyStyle()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        applyStyle()
    }

    override func mouseDown(with event: NSEvent) {
        dragOrigin = event.locationInWindow
        isDragging = false
        onSelect?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin else { return }
        if !isDragging {
            let distance = hypot(event.locationInWindow.x - origin.x, event.locationInWindow.y - origin.y)
            guard distance > 4 else { return }
            isDragging = true
            layer?.zPosition = 10
            onDragBegan?()
        }
        onDragMoved?(event)
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
        if isDragging {
            isDragging = false
            layer?.zPosition = 0
            onDragEnded?()
        }
    }

    // Middle-click closes, like every other browser.
    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 { onClose?() } else { super.otherMouseUp(with: event) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?()
    }

    @objc private func handleClose() {
        onClose?()
    }

    func apply(title: String,
               favicon: NSImage?,
               active: Bool,
               bypass: Bool,
               busy: Bool,
               muted: Bool,
               groupColor: NSColor?) {
        let display = title.isEmpty ? "New Tab" : title
        if titleLabel.stringValue != display { titleLabel.stringValue = display }
        toolTip = display

        hasFavicon = favicon != nil
        let icon = bypass ? Self.warning : (favicon ?? Self.globe)
        if iconView.image !== icon { iconView.image = icon }
        iconView.contentTintColor = bypass ? Theme.warn : Theme.muted

        if busy && !bypass {
            iconView.isHidden = true
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
            iconView.isHidden = false
        }

        if muteBadge.isHidden == muted {
            muteBadge.isHidden = !muted
            needsLayout = true
        }
        self.groupColor = groupColor
        groupBar.isHidden = groupColor == nil
        groupBar.layer?.backgroundColor = (groupColor ?? .clear).cgColor

        isActive = active
        hasBypass = bypass
        isBusy = busy
        applyStyle()
    }

    private func applyStyle() {
        let background: NSColor
        if isActive {
            background = Theme.panelHi
        } else if isHovering {
            background = Theme.panel
        } else {
            background = .clear
        }
        layer?.backgroundColor = background.cgColor
        layer?.borderWidth = hasBypass ? 1 : 0
        layer?.borderColor = Theme.warn.withAlphaComponent(0.7).cgColor
        titleLabel.textColor = isActive ? Theme.cream : Theme.bone
        closeButton.alphaValue = (isHovering || isActive) ? 1 : 0
    }
}
