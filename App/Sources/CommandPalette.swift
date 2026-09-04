import AppKit

struct PaletteCommand {
    let id: String
    let title: String
    let subtitle: String
    let run: () -> Void
}

final class CommandPalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PaletteRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let inset = bounds.insetBy(dx: 8, dy: 2)
        let path = NSBezierPath(roundedRect: inset, xRadius: 8, yRadius: 8)
        Theme.moss.withAlphaComponent(0.16).setFill()
        path.fill()
        Theme.moss.withAlphaComponent(0.55).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

final class CommandPaletteController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {

    private var panel: CommandPalettePanel?
    private var queryField: NSTextField?
    private var tableView: NSTableView?

    private var commands: [PaletteCommand] = []
    private var filtered: [PaletteCommand] = []

    var commandProvider: (() -> [PaletteCommand])?
    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle(relativeTo host: NSWindow) {
        if isVisible { dismiss() } else { present(relativeTo: host) }
    }

    func present(relativeTo host: NSWindow) {
        commands = commandProvider?() ?? []
        filtered = commands

        let panel = self.panel ?? makePanel()
        self.panel = panel

        queryField?.stringValue = ""
        tableView?.reloadData()
        selectRow(0)

        let size = panel.frame.size
        let hostFrame = host.frame
        let origin = NSPoint(
            x: hostFrame.midX - size.width / 2,
            y: hostFrame.midY - size.height / 2 + hostFrame.height * 0.14
        )
        panel.setFrameOrigin(origin)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        panel.contentView?.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.985, y: 0.985))
        Theme.animate(0.18) {
            panel.animator().alphaValue = 1
            panel.contentView?.layer?.setAffineTransform(.identity)
        }
        panel.makeFirstResponder(queryField)
    }

    func dismiss() {
        guard let panel else { return }
        Theme.animate(0.12) { panel.animator().alphaValue = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { panel.orderOut(nil) }
    }

    private func makePanel() -> CommandPalettePanel {
        let panel = CommandPalettePanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 380),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.appearance = NSAppearance(named: .darkAqua)

        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = Theme.panel.cgColor
        content.layer?.cornerRadius = 15
        content.layer?.borderWidth = 1
        content.layer?.borderColor = Theme.line2.cgColor
        content.layer?.shadowColor = Theme.acid.cgColor
        content.layer?.shadowOpacity = 0.1
        content.layer?.shadowRadius = 30
        content.layer?.shadowOffset = .zero
        panel.contentView = content

        let field = NSTextField()
        field.placeholderAttributedString = NSAttributedString(
            string: "Type a command",
            attributes: [.foregroundColor: Theme.muted, .font: NSFont.systemFont(ofSize: 17)]
        )
        field.font = .systemFont(ofSize: 17, weight: .regular)
        field.textColor = Theme.cream
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(field)
        queryField = field

        let caret = NSView()
        caret.wantsLayer = true
        caret.layer?.backgroundColor = Theme.acid.cgColor
        caret.layer?.cornerRadius = 1
        caret.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(caret)

        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = Theme.line.cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(separator)

        let table = NSTableView()
        table.headerView = nil
        table.rowHeight = 46
        table.dataSource = self
        table.delegate = self
        table.backgroundColor = .clear
        table.gridStyleMask = []
        table.selectionHighlightStyle = .regular
        table.allowsEmptySelection = false
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.target = self
        table.doubleAction = #selector(runSelectedCommand)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("command"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)
        tableView = table

        NSLayoutConstraint.activate([
            caret.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            caret.centerYAnchor.constraint(equalTo: field.centerYAnchor),
            caret.widthAnchor.constraint(equalToConstant: 2),
            caret.heightAnchor.constraint(equalToConstant: 18),

            field.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            field.leadingAnchor.constraint(equalTo: caret.trailingAnchor, constant: 12),
            field.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),

            separator.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 16),
            separator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            scroll.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8)
        ])

        return panel
    }

    private func selectRow(_ index: Int) {
        guard let table = tableView, index >= 0, index < filtered.count else { return }
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        table.scrollRowToVisible(index)
    }

    @objc private func runSelectedCommand() {
        guard let table = tableView else { return }
        let row = table.selectedRow
        guard row >= 0, row < filtered.count else { return }
        let command = filtered[row]
        dismiss()
        command.run()
    }

    func controlTextDidChange(_ obj: Notification) {
        let query = queryField?.stringValue.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        filtered = query.isEmpty ? commands : commands.filter {
            $0.title.lowercased().contains(query) || $0.subtitle.lowercased().contains(query)
        }
        tableView?.reloadData()
        selectRow(0)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            runSelectedCommand(); return true
        case #selector(NSResponder.cancelOperation(_:)):
            dismiss(); return true
        case #selector(NSResponder.moveDown(_:)):
            selectRow(min((tableView?.selectedRow ?? -1) + 1, filtered.count - 1)); return true
        case #selector(NSResponder.moveUp(_:)):
            selectRow(max((tableView?.selectedRow ?? 1) - 1, 0)); return true
        default:
            return false
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        PaletteRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filtered.count else { return nil }
        let command = filtered[row]

        let container = NSView()
        let title = NSTextField(labelWithString: command.title)
        title.font = .systemFont(ofSize: 13.5, weight: .medium)
        title.textColor = Theme.cream
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(labelWithString: command.subtitle)
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = Theme.muted
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(title)
        container.addSubview(subtitle)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 22),
            title.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -22),
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),

            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -22),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2)
        ])
        return container
    }
}
