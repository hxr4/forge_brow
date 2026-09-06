import AppKit

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String,
         enabled: Bool = true,
         state: NSControl.StateValue = .off,
         image: NSImage? = nil,
         handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        isEnabled = enabled
        self.state = state
        self.image = image
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}
