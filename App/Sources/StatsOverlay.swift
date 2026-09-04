import AppKit

enum StatsProbe {
    static let script = """
    (function(){var n=performance.getEntriesByType('navigation')[0]||{};\
    var r=performance.getEntriesByType('resource');var b=0;\
    for(var i=0;i<r.length;i++){b+=r[i].transferSize||0;}\
    var m=performance.memory||{};\
    return{nodes:document.getElementsByTagName('*').length,resources:r.length,\
    transferred:b+(n.transferSize||0),ttfb:Math.round(n.responseStart||0),\
    dcl:Math.round(n.domContentLoadedEventEnd||0),load:Math.round(n.loadEventEnd||0),\
    heap:m.usedJSHeapSize||0,heapLimit:m.jsHeapSizeLimit||0,\
    frames:window.frames.length,origin:location.origin};})()
    """
}

final class StatsOverlayView: NSView {

    private let titleLabel = NSTextField(labelWithString: "STATS FOR NERDS")
    private let hintLabel = NSTextField(labelWithString: "⌥⌘S")
    private var rowKeys: [NSTextField] = []
    private var rowValues: [NSTextField] = []
    private var rows: [(String, String)] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(rgb: 0x050604, alpha: 0.94).cgColor
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = Theme.line2.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.6
        layer?.shadowRadius = 24
        layer?.shadowOffset = NSSize(width: 0, height: -8)

        titleLabel.font = .systemFont(ofSize: 10, weight: .heavy)
        titleLabel.textColor = Theme.acid
        addSubview(titleLabel)

        hintLabel.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
        hintLabel.textColor = Theme.mossDeep
        hintLabel.alignment = .right
        addSubview(hintLabel)

        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    private static let rowHeight: CGFloat = 17
    private static let headerHeight: CGFloat = 30
    private static let padding: CGFloat = 13

    func apply(_ entries: [(String, String)]) {
        rows = entries

        while rowKeys.count < entries.count {
            let key = NSTextField(labelWithString: "")
            key.font = .systemFont(ofSize: 11)
            key.textColor = Theme.muted
            addSubview(key)
            rowKeys.append(key)

            let value = NSTextField(labelWithString: "")
            value.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            value.textColor = Theme.bone
            value.alignment = .right
            value.lineBreakMode = .byTruncatingMiddle
            addSubview(value)
            rowValues.append(value)
        }

        for (index, key) in rowKeys.enumerated() {
            let visible = index < entries.count
            key.isHidden = !visible
            rowValues[index].isHidden = !visible
            guard visible else { continue }
            if key.stringValue != entries[index].0 { key.stringValue = entries[index].0 }
            if rowValues[index].stringValue != entries[index].1 {
                rowValues[index].stringValue = entries[index].1
            }
        }

        needsLayout = true
    }

    var preferredHeight: CGFloat {
        Self.headerHeight + CGFloat(rows.count) * Self.rowHeight + Self.padding
    }

    override func layout() {
        super.layout()
        let pad = Self.padding
        titleLabel.frame = NSRect(x: pad, y: bounds.height - 22, width: 160, height: 13)
        hintLabel.frame = NSRect(x: bounds.width - pad - 60, y: bounds.height - 22, width: 60, height: 13)

        var y = bounds.height - Self.headerHeight
        let width = bounds.width - pad * 2
        for index in 0..<rows.count {
            y -= Self.rowHeight
            rowKeys[index].frame = NSRect(x: pad, y: y, width: width * 0.5, height: 14)
            rowValues[index].frame = NSRect(x: pad + width * 0.42, y: y,
                                            width: width * 0.58, height: 14)
        }
    }
}

enum StatsFormat {
    static func bytes(_ value: Double) -> String {
        guard value > 0 else { return "—" }
        let units = ["B", "KB", "MB", "GB"]
        var amount = value
        var index = 0
        while amount >= 1024, index < units.count - 1 {
            amount /= 1024
            index += 1
        }
        return String(format: amount >= 100 || index == 0 ? "%.0f %@" : "%.1f %@", amount, units[index])
    }

    static func millis(_ value: Double) -> String {
        guard value > 0 else { return "—" }
        return value >= 1000 ? String(format: "%.2f s", value / 1000) : String(format: "%.0f ms", value)
    }
}
