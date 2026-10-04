import AppKit
import AVFoundation
import CoreImage
import Vision

/// Where a link picked from the context menu should open.
enum LinkDestination {
    case foregroundTab
    case backgroundTab
    case newWindow
    case privateWindow
}

/// What the page context menu needs from the window that owns the tab.
protocol PageContextMenuHost: AnyObject {
    var isPrivateWindow: Bool { get }
    func open(_ url: String, in destination: LinkDestination)
    func searchWeb(for text: String, background: Bool)
    func toggleBookmark(url: String, title: String)
    func isBookmarked(url: String) -> Bool
    func addShortcut(url: String, title: String, tray: String?)
    func hideElement(in view: FGBrowserView, atCSS point: NSPoint)
    func restoreHiddenElements(in view: FGBrowserView)
    func hasHiddenElements(for url: String) -> Bool
}

/// The parameters CEF reports for a right-click, unpacked from FGClient.
struct ContextParams {
    let point: NSPoint
    let linkURL: String
    let linkText: String
    let sourceURL: String
    let pageURL: String
    let frameURL: String
    let selectionText: String
    let misspelledWord: String
    let suggestions: [String]
    let isEditable: Bool
    let typeFlags: Int
    let mediaType: Int
    let mediaFlags: Int
    let editFlags: Int
    let hasImageContents: Bool

    init(_ raw: [String: Any]) {
        func string(_ key: String) -> String { raw[key] as? String ?? "" }
        func int(_ key: String) -> Int { (raw[key] as? NSNumber)?.intValue ?? 0 }
        point = NSPoint(x: int("x"), y: int("y"))
        linkURL = string("linkURL")
        linkText = string("linkText")
        sourceURL = string("sourceURL")
        pageURL = string("pageURL")
        frameURL = string("frameURL")
        selectionText = string("selectionText").trimmingCharacters(in: .whitespacesAndNewlines)
        misspelledWord = string("misspelledWord")
        suggestions = raw["suggestions"] as? [String] ?? []
        isEditable = (raw["isEditable"] as? NSNumber)?.boolValue ?? false
        typeFlags = int("typeFlags")
        mediaType = int("mediaType")
        mediaFlags = int("mediaFlags")
        editFlags = int("editFlags")
        hasImageContents = (raw["hasImageContents"] as? NSNumber)?.boolValue ?? false
    }

    // Mirrors cef_context_menu_media_type_t / *_flags_t.
    var isImage: Bool { mediaType == 1 }
    var isVideo: Bool { mediaType == 2 }
    var isAudio: Bool { mediaType == 3 }
    var hasLink: Bool { !linkURL.isEmpty && !linkURL.hasPrefix("javascript:") }
    var hasSelection: Bool { !selectionText.isEmpty }

    var mediaPaused: Bool { mediaFlags & (1 << 1) != 0 }
    var mediaMuted: Bool { mediaFlags & (1 << 2) != 0 }
    var mediaLooping: Bool { mediaFlags & (1 << 3) != 0 }
    var mediaHasControls: Bool { mediaFlags & (1 << 7) != 0 }
    var mediaCanPiP: Bool { mediaFlags & (1 << 10) != 0 }
    var mediaInPiP: Bool { mediaFlags & (1 << 11) != 0 }

    var canUndo: Bool { editFlags & (1 << 0) != 0 }
    var canRedo: Bool { editFlags & (1 << 1) != 0 }
    var canCut: Bool { editFlags & (1 << 2) != 0 }
    var canCopy: Bool { editFlags & (1 << 3) != 0 }
    var canPaste: Bool { editFlags & (1 << 4) != 0 }
    var canDelete: Bool { editFlags & (1 << 5) != 0 }
    var canSelectAll: Bool { editFlags & (1 << 6) != 0 }
}

enum PageContextMenu {

    /// Finds a <video> under a CSS point even when the site covers it with an
    /// overlay (YouTube, Twitch), which hides it from Chromium's hit test.
    static func videoProbeScript(at point: NSPoint) -> String {
        """
        (function(x,y){
          var v=[].slice.call(document.querySelectorAll('video')).find(function(e){
            var r=e.getBoundingClientRect();return r.width>40&&x>=r.left&&x<=r.right&&y>=r.top&&y<=r.bottom;});
          if(!v) return null;
          return {paused:v.paused,muted:v.muted,loop:v.loop,controls:v.controls,
                  pip:document.pictureInPictureElement===v,time:Math.floor(v.currentTime||0),
                  src:(v.currentSrc&&v.currentSrc.indexOf('blob:')!==0)?v.currentSrc:''};
        })(\(Int(point.x)),\(Int(point.y)))
        """
    }

    static func cssPointForProbe(_ raw: [String: Any], in view: FGBrowserView) -> NSPoint {
        cssPoint(ContextParams(raw).point, in: view)
    }

    static func build(for raw: [String: Any],
                      tab: Tab,
                      host: PageContextMenuHost,
                      overlaidVideo: [String: Any]? = nil) -> NSMenu {
        let params = ContextParams(raw)
        let view = tab.browserView
        let menu = NSMenu()
        menu.autoenablesItems = false

        func add(_ title: String, enabled: Bool = true, symbol: String? = nil,
                 _ handler: @escaping () -> Void) {
            let item = ClosureMenuItem(title, enabled: enabled, handler: handler)
            if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
            menu.addItem(item)
        }
        func separator() {
            if let last = menu.items.last, !last.isSeparatorItem { menu.addItem(.separator()) }
        }

        // Spelling suggestions first, the way every Mac text field does it.
        if params.isEditable, !params.misspelledWord.isEmpty {
            if params.suggestions.isEmpty {
                add("No Guesses Found", enabled: false) {}
            }
            for word in params.suggestions.prefix(5) {
                let item = ClosureMenuItem(word) { view.replaceMisspelling(word) }
                item.attributedTitle = NSAttributedString(
                    string: word, attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
                menu.addItem(item)
            }
            separator()
        }

        if params.hasLink {
            let link = params.linkURL
            add("Open Link in New Tab") { host.open(link, in: .foregroundTab) }
            add("Open Link in Background Tab") { host.open(link, in: .backgroundTab) }
            add("Open Link in New Window") { host.open(link, in: .newWindow) }
            if !host.isPrivateWindow {
                add("Open Link in Private Window") { host.open(link, in: .privateWindow) }
            }
            separator()
            add("Copy Link Address") { Clipboard.copy(link) }
            let clean = LinkTools.clean(link)
            add(clean == link ? "Copy Clean Link" : "Copy Clean Link (tracking removed)") {
                Clipboard.copy(clean)
            }
            if !params.linkText.isEmpty, params.linkText != link {
                add("Copy Link Text") { Clipboard.copy(params.linkText) }
            }
            add("Save Link As…") { view.startDownload(link) }
            add("Create QR Code for This Link") { LinkTools.presentQRCode(for: link) }
            if !host.isPrivateWindow {
                let title = params.linkText.isEmpty ? link : params.linkText
                add("Bookmark Link") { host.toggleBookmark(url: link, title: title) }
                let trayMenu = NSMenu()
                for tray in Trays.all {
                    trayMenu.addItem(ClosureMenuItem(tray.name) {
                        host.addShortcut(url: link, title: title, tray: tray.name)
                    })
                }
                let trayItem = NSMenuItem(title: "Add Link to Shortcuts", action: nil, keyEquivalent: "")
                trayItem.submenu = trayMenu
                menu.addItem(trayItem)
            }
            separator()
        }

        if params.isImage, !params.sourceURL.isEmpty {
            let source = params.sourceURL
            let isData = source.hasPrefix("data:")
            add("Open Image in New Tab", enabled: !isData) { host.open(source, in: .foregroundTab) }
            add("Save Image As…") { view.startDownload(source) }
            add("Copy Image") {
                view.downloadImage(source) { image in
                    guard let image else { NSSound.beep(); return }
                    Clipboard.copy(image)
                }
            }
            add("Copy Image Address", enabled: !isData) { Clipboard.copy(source) }
            add("Copy Text from Image") {
                view.downloadImage(source) { image in
                    guard let image else { NSSound.beep(); return }
                    LinkTools.recognizeText(in: image) { text in
                        if let text, !text.isEmpty { Clipboard.copy(text) } else { NSSound.beep() }
                    }
                }
            }
            if !params.hasLink {
                add("Create QR Code for This Image") { LinkTools.presentQRCode(for: source) }
            }
            if !isData {
                add("Search Image with Google Lens") {
                    let encoded = source.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? source
                    host.open("https://lens.google.com/uploadbyurl?url=" + encoded, in: .foregroundTab)
                }
            }
            separator()
        }

        if params.isVideo || params.isAudio {
            let kind = params.isVideo ? "Video" : "Audio"
            let css = cssPoint(params.point, in: view)
            add(params.mediaPaused ? "Play" : "Pause") { runMedia("play", at: css, in: view) }
            add(params.mediaMuted ? "Unmute" : "Mute") { runMedia("mute", at: css, in: view) }
            let loop = ClosureMenuItem("Loop", state: params.mediaLooping ? .on : .off) {
                runMedia("loop", at: css, in: view)
            }
            menu.addItem(loop)
            let controls = ClosureMenuItem("Show Controls", state: params.mediaHasControls ? .on : .off) {
                runMedia("controls", at: css, in: view)
            }
            menu.addItem(controls)
            if params.isVideo {
                add(params.mediaInPiP ? "Exit Picture in Picture" : "Picture in Picture",
                    symbol: "pip.enter") { runMedia("pip", at: css, in: view) }
                add("Enter Full Screen", symbol: "arrow.up.left.and.arrow.down.right") {
                    runMedia("fullscreen", at: css, in: view)
                }
            }
            if !params.sourceURL.isEmpty, !params.sourceURL.hasPrefix("blob:") {
                let source = params.sourceURL
                add("Open \(kind) in New Tab") { host.open(source, in: .foregroundTab) }
                add("Save \(kind) As…") { view.startDownload(source) }
                add("Copy \(kind) Address") { Clipboard.copy(source) }
            }
            separator()
        }

        if let video = overlaidVideo, !params.isVideo, !params.isEditable {
            let css = cssPoint(params.point, in: view)
            func flag(_ key: String) -> Bool { (video[key] as? Bool) ?? false }
            add(flag("paused") ? "Play Video" : "Pause Video") { runMedia("play", at: css, in: view) }
            add(flag("muted") ? "Unmute" : "Mute") { runMedia("mute", at: css, in: view) }
            menu.addItem(ClosureMenuItem("Loop", state: flag("loop") ? .on : .off) {
                runMedia("loop", at: css, in: view)
            })
            add(flag("pip") ? "Exit Picture in Picture" : "Picture in Picture", symbol: "pip.enter") {
                runMedia("pip", at: css, in: view)
            }
            let seconds = (video["time"] as? NSNumber)?.intValue ?? 0
            if let timed = LinkTools.urlAtTime(params.pageURL, seconds: seconds) {
                add("Copy Video URL at \(LinkTools.clock(seconds))") { Clipboard.copy(timed) }
            }
            if let source = video["src"] as? String, !source.isEmpty {
                add("Open Video in New Tab") { host.open(source, in: .foregroundTab) }
                add("Save Video As…") { view.startDownload(source) }
            }
            separator()
        }

        if params.isEditable {
            add("Undo", enabled: params.canUndo) { view.editUndo() }
            add("Redo", enabled: params.canRedo) { view.editRedo() }
            separator()
            add("Cut", enabled: params.canCut) { view.editCut() }
            add("Copy", enabled: params.canCopy) { view.editCopy() }
            add("Paste", enabled: params.canPaste) { view.editPaste() }
            add("Paste and Match Style", enabled: params.canPaste) { view.editPasteAndMatchStyle() }
            add("Delete", enabled: params.canDelete) { view.editDelete() }
            add("Select All", enabled: params.canSelectAll) { view.editSelectAll() }
            separator()
        } else if params.hasSelection {
            let text = params.selectionText
            add("Copy") { view.editCopy() }
            let fragment = LinkTools.textFragmentURL(page: params.pageURL, selection: text)
            add("Copy Link to Highlight", enabled: fragment != nil) {
                if let fragment { Clipboard.copy(fragment) }
            }
            separator()
            let engine = SearchEngines.current.name
            add("Search \(engine) for “\(LinkTools.ellipsize(text, 28))”") {
                host.searchWeb(for: text, background: false)
            }
            if !text.contains("\n"), text.count < 60 {
                add("Look Up “\(LinkTools.ellipsize(text, 24))”") { LinkTools.lookUp(text) }
            }
            if let direct = LinkTools.urlIfLooksLikeOne(text) {
                add("Open “\(LinkTools.ellipsize(direct, 32))”") { host.open(direct, in: .foregroundTab) }
            }
            separator()
            let speech = NSMenu()
            speech.addItem(ClosureMenuItem("Start Speaking") { Speech.speak(text) })
            speech.addItem(ClosureMenuItem("Stop Speaking", enabled: Speech.isSpeaking) { Speech.stop() })
            let speechItem = NSMenuItem(title: "Speech", action: nil, keyEquivalent: "")
            speechItem.submenu = speech
            menu.addItem(speechItem)
            separator()
        }

        let plainPage = overlaidVideo == nil && !params.hasLink && !params.isImage && !params.isVideo && !params.isAudio
            && !params.isEditable && !params.hasSelection
        if plainPage {
            add("Back", enabled: tab.canGoBack, symbol: "chevron.left") { view.goBack() }
            add("Forward", enabled: tab.canGoForward, symbol: "chevron.right") { view.goForward() }
            add("Reload", symbol: "arrow.clockwise") { view.reload() }
            separator()
            let page = params.pageURL
            let isWeb = page.hasPrefix("http")
            add("Copy Page Address", enabled: isWeb) { Clipboard.copy(page) }
            add("Copy Clean Page Address", enabled: isWeb) { Clipboard.copy(LinkTools.clean(page)) }
            add("Create QR Code for This Page", enabled: isWeb) { LinkTools.presentQRCode(for: page) }
            if isWeb, !host.isPrivateWindow {
                add(host.isBookmarked(url: page) ? "Remove Bookmark" : "Bookmark This Page") {
                    host.toggleBookmark(url: page, title: tab.title)
                }
            }
            add("Print…") { view.printPage() }
            separator()
            if !params.frameURL.isEmpty, params.frameURL != params.pageURL {
                let frame = params.frameURL
                add("Open Frame in New Tab") { host.open(frame, in: .foregroundTab) }
                separator()
            }
        }

        // Element hiding works on anything that is not an input.
        if !params.isEditable, params.pageURL.hasPrefix("http") {
            let css = cssPoint(params.point, in: view)
            add("Hide This Element", symbol: "eye.slash") { host.hideElement(in: view, atCSS: css) }
            if host.hasHiddenElements(for: params.pageURL) {
                add("Restore Hidden Elements on This Site") { host.restoreHiddenElements(in: view) }
            }
        }
        add("View Page Source") { view.viewSource() }
        add("Inspect", symbol: "hammer") { view.showDevToolsInspectingPoint(params.point) }

        while menu.items.last?.isSeparatorItem == true { menu.removeItem(at: menu.items.count - 1) }
        return menu
    }

    /// CEF reports view points; the DOM wants CSS pixels, which differ under page zoom.
    private static func cssPoint(_ point: NSPoint, in view: FGBrowserView) -> NSPoint {
        let scale = max(0.25, CGFloat(view.zoomPercent()) / 100)
        return NSPoint(x: point.x / scale, y: point.y / scale)
    }

    private static func runMedia(_ operation: String, at point: NSPoint, in view: FGBrowserView) {
        let script = """
        (function(x,y,op){
          var hit=document.elementFromPoint(x,y);
          var m=hit&&hit.closest&&hit.closest('video,audio');
          if(!m){
            m=[].slice.call(document.querySelectorAll('video,audio')).find(function(v){
              var r=v.getBoundingClientRect();return x>=r.left&&x<=r.right&&y>=r.top&&y<=r.bottom;});
          }
          if(!m) return false;
          switch(op){
            case 'play': if(m.paused){m.play();}else{m.pause();} break;
            case 'mute': m.muted=!m.muted; break;
            case 'loop': m.loop=!m.loop; break;
            case 'controls': m.controls=!m.controls; break;
            case 'pip':
              if(document.pictureInPictureElement===m){document.exitPictureInPicture();}
              else if(m.requestPictureInPicture){m.disablePictureInPicture=false;m.requestPictureInPicture();}
              break;
            case 'fullscreen': (m.requestFullscreen||m.webkitRequestFullscreen).call(m); break;
          }
          return true;
        })(\(Int(point.x)),\(Int(point.y)),'\(operation)')
        """
        view.evaluateUserAction(script, completion: nil)
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }

    static func copy(_ image: NSImage) {
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects([image])
    }
}

enum Speech {
    private static let synthesizer = AVSpeechSynthesizer()

    static var isSpeaking: Bool { synthesizer.isSpeaking }

    static func speak(_ text: String) {
        stop()
        synthesizer.speak(AVSpeechUtterance(string: text))
    }

    static func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }
}

enum LinkTools {

    /// Query parameters that only exist to track clicks.
    private static let trackingKeys: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "mc_cid", "mc_eid",
        "igshid", "igsh", "si", "_hsenc", "_hsmi", "mkt_tok", "yclid", "twclid", "ttclid",
        "vero_id", "oly_anon_id", "oly_enc_id", "rb_clickid", "s_cid", "ref_src", "ref_url",
        "spm", "scm", "feature", "pp", "ved", "ei", "sca_esv", "sxsrf"
    ]

    static func clean(_ raw: String) -> String {
        guard var components = URLComponents(string: raw), let items = components.queryItems else {
            return raw
        }
        let kept = items.filter { item in
            let key = item.name.lowercased()
            return !key.hasPrefix("utm_") && !key.hasPrefix("pk_") && !trackingKeys.contains(key)
        }
        guard kept.count != items.count else { return raw }
        components.queryItems = kept.isEmpty ? nil : kept
        return components.string ?? raw
    }

    static func textFragmentURL(page: String, selection: String) -> String? {
        guard page.hasPrefix("http"), !selection.isEmpty else { return nil }
        let base = page.components(separatedBy: "#").first ?? page
        let words = selection.split(whereSeparator: { $0.isWhitespace })
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&,-#")
        func encode(_ text: String) -> String { text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text }
        let fragment: String
        if words.count > 10 {
            let start = words.prefix(4).joined(separator: " ")
            let end = words.suffix(4).joined(separator: " ")
            fragment = encode(start) + "," + encode(end)
        } else {
            fragment = encode(words.joined(separator: " "))
        }
        return base + "#:~:text=" + fragment
    }

    /// Adds a start time to video pages that understand one (YouTube's `t=`).
    static func urlAtTime(_ page: String, seconds: Int) -> String? {
        guard seconds > 0, var components = URLComponents(string: page),
              let host = components.host, host.contains("youtube.com") || host == "youtu.be" else { return nil }
        var items = (components.queryItems ?? []).filter { $0.name != "t" }
        items.append(URLQueryItem(name: "t", value: "\(seconds)s"))
        components.queryItems = items
        return components.string.map(clean)
    }

    static func clock(_ seconds: Int) -> String {
        let h = seconds / 3600, m = seconds / 60 % 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func ellipsize(_ text: String, _ limit: Int) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }

    static func urlIfLooksLikeOne(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(" "), trimmed.count < 2048 else { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return trimmed }
        let looksLikeHost = trimmed.range(of: #"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+(/\S*)?$"#,
                                         options: .regularExpression) != nil
        return looksLikeHost ? "https://" + trimmed : nil
    }

    static func lookUp(_ word: String) {
        guard let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "dict://" + encoded) else { return }
        NSWorkspace.shared.open(url)
    }

    static func recognizeText(in image: NSImage, completion: @escaping (String?) -> Void) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion(nil)
            return
        }
        let request = VNRecognizeTextRequest { request, _ in
            let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
            DispatchQueue.main.async { completion(lines.joined(separator: "\n")) }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try VNImageRequestHandler(cgImage: cg).perform([request])
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    static func qrImage(for text: String, size: CGFloat = 220) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    static func presentQRCode(for text: String) {
        guard let image = qrImage(for: text) else { NSSound.beep(); return }
        let alert = NSAlert()
        alert.messageText = "QR Code"
        alert.informativeText = ellipsize(text, 80)
        let well = NSImageView(frame: NSRect(x: 0, y: 0, width: 220, height: 220))
        well.image = image
        well.wantsLayer = true
        well.layer?.backgroundColor = NSColor.white.cgColor
        well.layer?.cornerRadius = 6
        alert.accessoryView = well
        alert.addButton(withTitle: "Done")
        alert.addButton(withTitle: "Copy Image")
        if alert.runModal() == .alertSecondButtonReturn {
            Clipboard.copy(image)
        }
    }
}
