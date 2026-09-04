import AppKit
import Foundation

final class Tab {
    let id = UUID()
    let browserView: FGBrowserView

    var title: String
    var url: String
    var favicon: NSImage?
    var isLoading = false
    var canGoBack = false
    var canGoForward = false

    var ignoresCertificateErrors: Bool {
        get { browserView.bypassOptions.contains(.certificateErrors) }
        set {
            if newValue {
                browserView.bypassOptions = [.certificateErrors]
            } else {
                browserView.bypassOptions = []
            }
        }
    }

    var hasActiveBypass: Bool { ignoresCertificateErrors }

    var displayTitle: String {
        if !title.isEmpty { return title }
        if !url.isEmpty { return url }
        return "New Tab"
    }

    init(url: String) {
        self.url = url
        self.title = ""
        self.favicon = FaviconStore.shared.icon(for: url)
        self.browserView = FGBrowserView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800),
                                         initialURL: url)
        self.browserView.translatesAutoresizingMaskIntoConstraints = false
    }
}
