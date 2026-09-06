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
    frames:window.frames.length,origin:location.origin,\
    defused:window.__forgeDefused||0};})()
    """
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

final class SpectrumView: NSView {
    private var levels: [Double] = []
    private var peaks: [Double] = []

    func apply(_ values: [Double]) {
        levels = values
        if peaks.count != values.count { peaks = values }
        for index in values.indices {
            peaks[index] = max(values[index], peaks[index] - 0.045)
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !levels.isEmpty else { return }
        let count = CGFloat(levels.count)
        let gap: CGFloat = 2
        let width = max(1, (bounds.width - gap * (count - 1)) / count)

        for (index, level) in levels.enumerated() {
            let x = CGFloat(index) * (width + gap)
            let height = max(1, bounds.height * CGFloat(level))
            let ratio = CGFloat(index) / max(1, count - 1)
            let color = Theme.moss.blended(withFraction: ratio * 0.85, of: Theme.acid) ?? Theme.moss
            color.withAlphaComponent(0.92).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: 0, width: width, height: height),
                         xRadius: width / 2, yRadius: width / 2).fill()

            let peak = bounds.height * CGFloat(peaks[index])
            if peak > height + 1 {
                Theme.cream.withAlphaComponent(0.5).setFill()
                NSBezierPath(rect: NSRect(x: x, y: peak, width: width, height: 1)).fill()
            }
        }
    }
}

final class StatsContentView: NSView {

    static let rowHeight: CGFloat = 17
    static let headerHeight: CGFloat = 25
    static let padding: CGFloat = 13
    static let spectrumHeight: CGFloat = 36

    private var sections: [(String, [(String, String)])] = []
    private var spectrumValues: [Double] = []

    private var titles: [NSTextField] = []
    private var keys: [NSTextField] = []
    private var values: [NSTextField] = []
    private var rules: [NSView] = []
    private let spectrum = SpectrumView()

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        spectrum.isHidden = true
        addSubview(spectrum)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func title(at index: Int) -> NSTextField {
        while titles.count <= index {
            let label = NSTextField(labelWithString: "")
            label.font = .systemFont(ofSize: 10, weight: .heavy)
            addSubview(label)
            titles.append(label)

            let rule = NSView()
            rule.wantsLayer = true
            rule.layer?.backgroundColor = Theme.line.cgColor
            addSubview(rule)
            rules.append(rule)
        }
        return titles[index]
    }

    private func row(at index: Int) -> (NSTextField, NSTextField) {
        while keys.count <= index {
            let key = NSTextField(labelWithString: "")
            key.font = .systemFont(ofSize: 11)
            key.textColor = Theme.muted
            addSubview(key)
            keys.append(key)

            let value = NSTextField(labelWithString: "")
            value.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            value.textColor = Theme.bone
            value.alignment = .right
            value.lineBreakMode = .byTruncatingMiddle
            addSubview(value)
            values.append(value)
        }
        return (keys[index], values[index])
    }

    var contentHeight: CGFloat {
        var height = Self.padding
        for (index, section) in sections.enumerated() {
            height += index == 0 ? Self.headerHeight : Self.headerHeight + 8
            height += CGFloat(section.1.count) * Self.rowHeight
        }
        if !spectrumValues.isEmpty { height += Self.spectrumHeight + 10 }
        return height + Self.padding
    }

    func apply(sections newSections: [(String, [(String, String)])], spectrum newSpectrum: [Double]) {
        sections = newSections
        spectrumValues = newSpectrum
        spectrum.isHidden = newSpectrum.isEmpty
        spectrum.apply(newSpectrum)

        var rowIndex = 0
        for (sectionIndex, section) in sections.enumerated() {
            let header = title(at: sectionIndex)
            header.stringValue = section.0
            header.textColor = sectionIndex == 0 ? Theme.acid : Theme.moss
            header.isHidden = false
            rules[sectionIndex].isHidden = sectionIndex == 0

            for entry in section.1 {
                let (key, value) = row(at: rowIndex)
                key.isHidden = false
                value.isHidden = false
                if key.stringValue != entry.0 { key.stringValue = entry.0 }
                if value.stringValue != entry.1 { value.stringValue = entry.1 }
                rowIndex += 1
            }
        }

        for index in sections.count..<titles.count {
            titles[index].isHidden = true
            rules[index].isHidden = true
        }
        for index in rowIndex..<keys.count {
            keys[index].isHidden = true
            values[index].isHidden = true
        }

        needsLayout = true
    }

    override func layout() {
        super.layout()
        let pad = Self.padding
        let width = bounds.width - pad * 2
        var y = pad
        var rowIndex = 0

        for (sectionIndex, section) in sections.enumerated() {
            if sectionIndex > 0 {
                y += 8
                rules[sectionIndex].frame = NSRect(x: pad, y: y - 5, width: width, height: 1)
            }
            titles[sectionIndex].frame = NSRect(x: pad, y: y, width: width, height: 13)
            y += Self.headerHeight

            for _ in section.1 {
                keys[rowIndex].frame = NSRect(x: pad, y: y, width: width * 0.5, height: 14)
                values[rowIndex].frame = NSRect(x: pad + width * 0.40, y: y,
                                                width: width * 0.60, height: 14)
                y += Self.rowHeight
                rowIndex += 1
            }
        }

        if !spectrumValues.isEmpty {
            y += 8
            spectrum.frame = NSRect(x: pad, y: y, width: width, height: Self.spectrumHeight)
        }
    }
}

final class StatsOverlayView: NSView {

    private let scroll = NSScrollView()
    private let content = StatsContentView()
    private let hint = NSTextField(labelWithString: "⌥⌘S")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(rgb: 0x050604, alpha: 0.95).cgColor
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = Theme.line2.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.6
        layer?.shadowRadius = 26
        layer?.shadowOffset = NSSize(width: 0, height: -8)

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        scroll.documentView = content
        addSubview(scroll)

        hint.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
        hint.textColor = Theme.mossDeep
        hint.alignment = .right
        addSubview(hint)

        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    var contentHeight: CGFloat { content.contentHeight }

    func apply(sections: [(String, [(String, String)])], spectrum values: [Double]) {
        content.apply(sections: sections, spectrum: values)
        let width = max(1, bounds.width - 2)
        content.frame = NSRect(x: 0, y: 0, width: width, height: content.contentHeight)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        scroll.frame = bounds.insetBy(dx: 1, dy: 1)
        content.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width,
                               height: max(content.contentHeight, scroll.contentSize.height))
        hint.frame = NSRect(x: bounds.width - 52, y: bounds.height - 22, width: 40, height: 13)
    }
}
