import AppKit
import Foundation

struct TabGroup: Identifiable, Equatable {
    let id: UUID
    var name: String
    var colorIndex: Int
    var isCollapsed: Bool

    init(name: String, colorIndex: Int) {
        self.id = UUID()
        self.name = name
        self.colorIndex = colorIndex
        self.isCollapsed = false
    }

    var color: NSColor { Theme.groupPalette[colorIndex % Theme.groupPalette.count] }
}

final class Tab {
    let id = UUID()
    let browserView: FGBrowserView

    var title: String
    var url: String
    var favicon: NSImage?
    var media: NowPlaying?
    var groupID: UUID?

    var isMuted: Bool {
        get { browserView.isAudioMuted }
        set { browserView.setAudioMuted(newValue) }
    }
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

    let isPrivate: Bool

    init(url: String, isPrivate: Bool = false) {
        self.url = url
        self.title = ""
        self.isPrivate = isPrivate
        self.favicon = FaviconStore.shared.icon(for: url)
        self.browserView = FGBrowserView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800),
                                         initialURL: url,
                                         privateBrowsing: isPrivate)
        self.browserView.translatesAutoresizingMaskIntoConstraints = false
    }
}
