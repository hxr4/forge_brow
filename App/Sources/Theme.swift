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

enum Theme {
    static let void = NSColor(rgb: 0x000000)
    static let ink = NSColor(rgb: 0x070806)
    static let panel = NSColor(rgb: 0x0C0E0B)
    static let panelHi = NSColor(rgb: 0x141810)
    static let line = NSColor(rgb: 0x1E2318)
    static let line2 = NSColor(rgb: 0x2C3322)

    static let moss = NSColor(rgb: 0x96965A)
    static let mossDeep = NSColor(rgb: 0x585738)
    static let mossLift = NSColor(rgb: 0xB3B472)
    static let acid = NSColor(rgb: 0xCFE85C)

    static let cream = NSColor(rgb: 0xF4F2E7)
    static let bone = NSColor(rgb: 0xB9BBA8)
    static let muted = NSColor(rgb: 0x6B6F5E)
    static let warn = NSColor(rgb: 0xFF8A3D)

    static let groupPalette: [NSColor] = [
        NSColor(rgb: 0x96965A),
        NSColor(rgb: 0xCFE85C),
        NSColor(rgb: 0x5CC8E8),
        NSColor(rgb: 0xA98CE8),
        NSColor(rgb: 0x5CE8A0),
        NSColor(rgb: 0xE85C9A)
    ]

    enum Metrics {
        static let tabHeight: CGFloat = 30
        static let tabRadius: CGFloat = 8
        static let stripInset: CGFloat = 8
        static let sidebarWidth: CGFloat = 208
        static let toolbarHeight: CGFloat = 46
    }

    static func animate(_ duration: CFTimeInterval = 0.22, _ body: () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.61, 0.36, 1)
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
