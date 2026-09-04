import AppKit

final class TabItemView: NSView {

    let tabID: UUID

    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let iconSlot = NSView()
    private let iconView = NSImageView()
    private let statusDot = NSView()
    private let closeButton = NSButton()
    private let groupBar = NSView()
    private var groupColor: NSColor?
    private var trackingArea: NSTrackingArea?

    private var isActive = false
    private var isHovering = false
    private var hasBypass = false
    private var isBusy = false

    init(tabID: UUID) {
        self.tabID = tabID
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Theme.Metrics.tabRadius
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.clear.cgColor
        layer?.backgroundColor = NSColor.clear.cgColor

        groupBar.wantsLayer = true
        groupBar.layer?.cornerRadius = 1
        groupBar.isHidden = true
        addSubview(groupBar)

        iconSlot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconSlot)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 2
        iconView.isHidden = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconSlot.addSubview(iconView)

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 3
        statusDot.layer?.backgroundColor = Theme.mossDeep.cgColor
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        iconSlot.addSubview(statusDot)

        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = Theme.muted
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(titleLabel)

        closeButton.title = "✕"
        closeButton.font = .systemFont(ofSize: 9, weight: .bold)
        closeButton.isBordered = false
        closeButton.contentTintColor = Theme.muted
        closeButton.target = self
        closeButton.action = #selector(handleClose)
        closeButton.alphaValue = 0
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            iconSlot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconSlot.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconSlot.widthAnchor.constraint(equalToConstant: 15),
            iconSlot.heightAnchor.constraint(equalToConstant: 15),

            iconView.leadingAnchor.constraint(equalTo: iconSlot.leadingAnchor),
            iconView.trailingAnchor.constraint(equalTo: iconSlot.trailingAnchor),
            iconView.topAnchor.constraint(equalTo: iconSlot.topAnchor),
            iconView.bottomAnchor.constraint(equalTo: iconSlot.bottomAnchor),

            statusDot.centerXAnchor.constraint(equalTo: iconSlot.centerXAnchor),
            statusDot.centerYAnchor.constraint(equalTo: iconSlot.centerYAnchor),
            statusDot.widthAnchor.constraint(equalToConstant: 6),
            statusDot.heightAnchor.constraint(equalToConstant: 6),

            titleLabel.leadingAnchor.constraint(equalTo: iconSlot.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -6),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 14),
            closeButton.heightAnchor.constraint(equalToConstant: 14)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

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
        applyStyle(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        applyStyle(animated: true)
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }

    @objc private func handleClose() {
        onClose?()
    }

    override func layout() {
        super.layout()
        groupBar.frame = NSRect(x: 2, y: 6, width: 2, height: max(0, bounds.height - 12))
    }

    func apply(title: String,
               favicon: NSImage?,
               active: Bool,
               bypass: Bool,
               busy: Bool,
               groupColor: NSColor?) {
        let display = title.isEmpty ? "New Tab" : title
        if titleLabel.stringValue != display { titleLabel.stringValue = display }
        toolTip = display

        let showsIcon = favicon != nil && !bypass && !busy
        if iconView.image !== favicon { iconView.image = favicon }
        iconView.isHidden = !showsIcon
        statusDot.isHidden = showsIcon

        self.groupColor = groupColor
        groupBar.isHidden = groupColor == nil || bypass
        groupBar.layer?.backgroundColor = (groupColor ?? .clear).cgColor

        let changed = active != isActive || bypass != hasBypass || busy != isBusy
        isActive = active
        hasBypass = bypass
        isBusy = busy
        if changed { applyStyle(animated: true) } else { applyStyle(animated: false) }
    }

    private func applyStyle(animated: Bool) {
        let background: NSColor
        let border: NSColor
        let text: NSColor

        if hasBypass {
            background = isActive ? Theme.warn.withAlphaComponent(0.14) : NSColor.clear
            border = Theme.warn
            text = isActive ? Theme.cream : Theme.bone
        } else if isActive {
            background = Theme.panelHi
            border = groupColor ?? Theme.moss
            text = Theme.cream
        } else if isHovering {
            background = Theme.panel
            border = Theme.line2
            text = Theme.bone
        } else {
            background = NSColor.clear
            border = NSColor.clear
            text = Theme.muted
        }

        let dot: NSColor = hasBypass ? Theme.warn : (isBusy ? Theme.acid : (isActive ? Theme.moss : Theme.mossDeep))

        let work = {
            self.layer?.backgroundColor = background.cgColor
            self.layer?.borderColor = border.cgColor
            self.titleLabel.textColor = text
            self.statusDot.layer?.backgroundColor = dot.cgColor
            self.closeButton.animator().alphaValue = (self.isHovering || self.isActive) ? 1 : 0
        }

        if animated { Theme.animate(0.2, work) } else { work() }

        if isActive && !hasBypass {
            layer?.shadowColor = Theme.acid.cgColor
            layer?.shadowOpacity = 0.22
            layer?.shadowRadius = 10
            layer?.shadowOffset = .zero
        } else if hasBypass {
            layer?.shadowColor = Theme.warn.cgColor
            layer?.shadowOpacity = 0.3
            layer?.shadowRadius = 9
            layer?.shadowOffset = .zero
        } else {
            layer?.shadowOpacity = 0
        }
    }
}
