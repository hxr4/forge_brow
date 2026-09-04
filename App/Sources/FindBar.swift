import AppKit

final class FindBar: NSView, NSTextFieldDelegate {

    var onQueryChange: ((String) -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onClose: (() -> Void)?

    private let field = NSTextField()
    private let countLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.panel.cgColor
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = Theme.line2.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.6
        layer?.shadowRadius = 18
        layer?.shadowOffset = NSSize(width: 0, height: -4)

        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.textColor = Theme.cream
        field.delegate = self
        field.placeholderAttributedString = NSAttributedString(
            string: "Find in page",
            attributes: [.foregroundColor: Theme.muted, .font: NSFont.systemFont(ofSize: 13)]
        )
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)

        countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        countLabel.textColor = Theme.muted
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(countLabel)

        let previous = makeButton("‹", action: #selector(handlePrevious))
        let next = makeButton("›", action: #selector(handleNext))
        let close = makeButton("✕", action: #selector(handleClose))
        close.font = .systemFont(ofSize: 11, weight: .semibold)

        let stack = NSStackView(views: [previous, next, close])
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
            field.widthAnchor.constraint(equalToConstant: 210),

            countLabel.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 10),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            countLabel.widthAnchor.constraint(equalToConstant: 66),

            stack.leadingAnchor.constraint(equalTo: countLabel.trailingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    private func makeButton(_ glyph: String, action: Selector) -> NSButton {
        let button = NSButton(title: glyph, target: self, action: action)
        button.isBordered = false
        button.font = .systemFont(ofSize: 14)
        button.contentTintColor = Theme.bone
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        return button
    }

    var query: String { field.stringValue }

    func focus() {
        window?.makeFirstResponder(field)
        field.selectText(nil)
    }

    func setMatches(count: Int, active: Int) {
        countLabel.stringValue = count == 0 ? (field.stringValue.isEmpty ? "" : "no matches") : "\(active) of \(count)"
        countLabel.textColor = count == 0 && !field.stringValue.isEmpty ? Theme.warn : Theme.muted
    }

    @objc private func handleNext() { onNext?() }
    @objc private func handlePrevious() { onPrevious?() }
    @objc private func handleClose() { onClose?() }

    func controlTextDidChange(_ obj: Notification) {
        onQueryChange?(field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)): onNext?(); return true
        case #selector(NSResponder.cancelOperation(_:)): onClose?(); return true
        default: return false
        }
    }
}
