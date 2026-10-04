import AppKit

extension NSColor {
    convenience init(rgb: Int, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}

/// Forge v2 palette: graphite neutrals so the page is the brightest thing on
/// screen, and a single accent reserved for focus, progress and selection.
/// Text tokens all clear WCAG AA (4.5:1) against `ink`.
enum Theme {
    // Surfaces, darkest to lightest.
    static let void = NSColor(rgb: 0x0F0F10)      // behind web content
    static let ink = NSColor(rgb: 0x19191B)       // window chrome: tab strip + toolbar
    static let panel = NSColor(rgb: 0x232326)     // fields, hover
    static let panelHi = NSColor(rgb: 0x2E2E32)   // selected tab, pressed
    static let line = NSColor(rgb: 0x2A2A2E)      // hairlines
    static let line2 = NSColor(rgb: 0x3A3A3F)     // stronger hairlines, disabled glyphs

    // Brand. Olive is the identity colour, acid is the single attention colour.
    static let moss = NSColor(rgb: 0xA4A86A)
    static let mossDeep = NSColor(rgb: 0x55573D)
    static let mossLift = NSColor(rgb: 0xC2C68A)
    static let acid = NSColor(rgb: 0xCFE85C)
    static let accent = acid

    // Text.
    static let cream = NSColor(rgb: 0xEDEDEF)     // primary  (14.6:1 on ink)
    static let bone = NSColor(rgb: 0xB5B5BC)      // secondary (8.4:1)
    static let muted = NSColor(rgb: 0x8C8C94)     // tertiary  (5.2:1)

    static let warn = NSColor(rgb: 0xFF9F43)
    static let danger = NSColor(rgb: 0xFF6B5E)
    static let privateAccent = NSColor(rgb: 0xB49CF0)

    static let groupPalette: [NSColor] = [
        NSColor(rgb: 0xA4A86A),
        NSColor(rgb: 0xCFE85C),
        NSColor(rgb: 0x5CC8E8),
        NSColor(rgb: 0xB49CF0),
        NSColor(rgb: 0x5CE8A0),
        NSColor(rgb: 0xF07FAE)
    ]

    enum Metrics {
        static let tabHeight: CGFloat = 28
        static let tabRadius: CGFloat = 7
        static let stripInset: CGFloat = 6
        static let sidebarWidth: CGFloat = 232      // vertical tab column
        static let toolbarHeight: CGFloat = 40
        static let stripHeight: CGFloat = 38
        static let trafficLightInset: CGFloat = 80
        static let controlHeight: CGFloat = 28
    }

    static func animate(_ duration: CFTimeInterval = 0.18, _ body: () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            body()
        }
    }
}

enum TabOrientation: String {
    case horizontal
    case vertical

    var flipped: TabOrientation { self == .horizontal ? .vertical : .horizontal }
}

/// Borderless SF Symbol button with a quiet hover/pressed plate, used for all
/// toolbar and strip controls so they share one size, weight and hit target.
final class ChromeButton: NSButton {
    private var tracking: NSTrackingArea?
    private var hovering = false { didSet { restyle() } }

    var tint: NSColor = Theme.bone { didSet { restyle() } }
    var isToggled = false { didSet { restyle() } }

    convenience init(symbol: String, label: String, pointSize: CGFloat = 14,
                     weight: NSFont.Weight = .regular, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        setSymbol(symbol, label: label, pointSize: pointSize, weight: weight)
        self.target = target
        self.action = action
        toolTip = label
        setAccessibilityLabel(label)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        title = ""
        wantsLayer = true
        layer?.cornerRadius = 6
        focusRingType = .none
        restyle()
    }

    required init?(coder: NSCoder) { fatalError() }

    func setSymbol(_ name: String, label: String, pointSize: CGFloat = 14, weight: NSFont.Weight = .regular) {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        image = NSImage(systemSymbolName: name, accessibilityDescription: label)?
            .withSymbolConfiguration(config)
    }

    override var isEnabled: Bool { didSet { restyle() } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = Theme.panelHi.cgColor
        super.mouseDown(with: event)
        restyle()
    }

    private func restyle() {
        contentTintColor = isEnabled ? (isToggled ? Theme.accent : tint) : Theme.line2
        let plate: NSColor = (hovering && isEnabled) || isToggled ? Theme.panel : .clear
        layer?.backgroundColor = plate.cgColor
    }
}
