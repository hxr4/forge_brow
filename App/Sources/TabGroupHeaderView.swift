import AppKit

final class TabGroupHeaderView: NSView {

    let groupID: UUID
    var onToggle: (() -> Void)?

    private let dot = NSView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private var measuredWidth: CGFloat = 70

    init(groupID: UUID) {
        self.groupID = groupID
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Theme.Metrics.tabRadius
        layer?.borderWidth = 1

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        addSubview(dot)

        nameLabel.font = .systemFont(ofSize: 11, weight: .bold)
        nameLabel.lineBreakMode = .byTruncatingTail
        addSubview(nameLabel)

        countLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        countLabel.textColor = Theme.muted
        addSubview(countLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) { onToggle?() }

    var preferredWidth: CGFloat { measuredWidth }

    func apply(_ group: TabGroup, count: Int) {
        nameLabel.stringValue = group.name
        countLabel.stringValue = group.isCollapsed ? "\(count)" : "·"

        let color = group.color
        dot.layer?.backgroundColor = color.cgColor
        nameLabel.textColor = color
        layer?.borderColor = color.withAlphaComponent(0.55).cgColor
        layer?.backgroundColor = color.withAlphaComponent(group.isCollapsed ? 0.16 : 0.08).cgColor

        let nameWidth = nameLabel
            .sizeThatFits(NSSize(width: CGFloat.greatestFiniteMagnitude, height: 14)).width
        measuredWidth = min(150, 22 + nameWidth + 6 + (group.isCollapsed ? 16 : 8) + 10)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let height = bounds.height
        dot.frame = NSRect(x: 9, y: (height - 6) / 2, width: 6, height: 6)
        let nameX: CGFloat = 21
        let countWidth: CGFloat = 18
        nameLabel.frame = NSRect(x: nameX, y: (height - 14) / 2,
                                 width: max(10, bounds.width - nameX - countWidth - 8), height: 14)
        countLabel.frame = NSRect(x: bounds.width - countWidth - 7, y: (height - 13) / 2,
                                  width: countWidth, height: 13)
    }
}
