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
            let bar = NSRect(x: x, y: 0, width: width, height: height)
            let ratio = CGFloat(index) / max(1, count - 1)
            let color = Theme.moss.blended(withFraction: ratio * 0.85, of: Theme.acid) ?? Theme.moss
            color.withAlphaComponent(0.92).setFill()
            NSBezierPath(roundedRect: bar, xRadius: width / 2, yRadius: width / 2).fill()

            let peak = bounds.height * CGFloat(peaks[index])
            if peak > height + 1 {
                Theme.cream.withAlphaComponent(0.5).setFill()
                NSBezierPath(rect: NSRect(x: x, y: peak, width: width, height: 1)).fill()
            }
        }
    }
}

final class StatsOverlayView: NSView {

    private let titleLabel = NSTextField(labelWithString: "STATS FOR NERDS")
    private let hintLabel = NSTextField(labelWithString: "⌥⌘S")
    private var rowKeys: [NSTextField] = []
    private var rowValues: [NSTextField] = []
    private var rows: [(String, String)] = []

    private let audioTitle = NSTextField(labelWithString: "AUDIO PATH")
    private let divider = NSView()
    private let spectrum = SpectrumView()
    private var audioKeys: [NSTextField] = []
    private var audioValues: [NSTextField] = []
    private var audioRows: [(String, String)] = []
    private var audioVisible = false

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

        audioTitle.font = .systemFont(ofSize: 10, weight: .heavy)
        audioTitle.textColor = Theme.moss
        audioTitle.isHidden = true
        addSubview(audioTitle)

        divider.wantsLayer = true
        divider.layer?.backgroundColor = Theme.line.cgColor
        divider.isHidden = true
        addSubview(divider)

        spectrum.isHidden = true
        addSubview(spectrum)

        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    private static let spectrumHeight: CGFloat = 34

    func applyAudio(_ entries: [(String, String)], spectrum values: [Double]) {
        audioRows = entries
        audioVisible = !entries.isEmpty

        audioTitle.isHidden = !audioVisible
        divider.isHidden = !audioVisible
        spectrum.isHidden = !audioVisible
        spectrum.apply(values)

        while audioKeys.count < entries.count {
            let key = NSTextField(labelWithString: "")
            key.font = .systemFont(ofSize: 11)
            key.textColor = Theme.muted
            addSubview(key)
            audioKeys.append(key)

            let value = NSTextField(labelWithString: "")
            value.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            value.textColor = Theme.cream
            value.alignment = .right
            value.lineBreakMode = .byTruncatingMiddle
            addSubview(value)
            audioValues.append(value)
        }

        for (index, key) in audioKeys.enumerated() {
            let visible = index < entries.count
            key.isHidden = !visible
            audioValues[index].isHidden = !visible
            guard visible else { continue }
            if key.stringValue != entries[index].0 { key.stringValue = entries[index].0 }
            if audioValues[index].stringValue != entries[index].1 {
                audioValues[index].stringValue = entries[index].1
            }
        }

        needsLayout = true
    }

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
        var height = Self.headerHeight + CGFloat(rows.count) * Self.rowHeight + Self.padding
        if audioVisible {
            height += 14 + 18 + CGFloat(audioRows.count) * Self.rowHeight + Self.spectrumHeight + 10
        }
        return height
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

        guard audioVisible else { return }

        y -= 12
        divider.frame = NSRect(x: pad, y: y, width: width, height: 1)
        y -= 17
        audioTitle.frame = NSRect(x: pad, y: y, width: 160, height: 13)

        for index in 0..<audioRows.count {
            y -= Self.rowHeight
            audioKeys[index].frame = NSRect(x: pad, y: y, width: width * 0.5, height: 14)
            audioValues[index].frame = NSRect(x: pad + width * 0.42, y: y,
                                              width: width * 0.58, height: 14)
        }

        y -= Self.spectrumHeight + 8
        spectrum.frame = NSRect(x: pad, y: y, width: width, height: Self.spectrumHeight)
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
