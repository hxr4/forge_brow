import AppKit

struct NowPlaying: Equatable {
    var title: String
    var artist: String
    var artworkURL: String
    var playing: Bool
    var muted: Bool
    var position: Double
    var duration: Double

    init?(_ payload: [String: Any]) {
        guard let title = payload["title"] as? String, !title.isEmpty else { return nil }
        self.title = title
        artist = payload["artist"] as? String ?? ""
        artworkURL = payload["artwork"] as? String ?? ""
        playing = payload["playing"] as? Bool ?? false
        muted = payload["muted"] as? Bool ?? false
        position = payload["position"] as? Double ?? 0
        duration = payload["duration"] as? Double ?? 0
    }
}

enum MediaProbe {
    static let script = """
    (function(){var m=[].slice.call(document.querySelectorAll('video,audio'));var v=null;\
    for(var i=0;i<m.length;i++){var e=m[i];if(!e.muted&&e.currentTime>0&&!e.ended&&e.readyState>0){v=e;break;}}\
    var s=navigator.mediaSession&&navigator.mediaSession.metadata;if(!v&&!s)return null;\
    var art='';if(s&&s.artwork&&s.artwork.length){art=s.artwork[s.artwork.length-1].src;}\
    return{playing:v?!v.paused:false,title:(s&&s.title)||document.title||'',\
    artist:(s&&s.artist)||location.hostname,artwork:art,muted:v?!!v.muted:false,\
    position:v?v.currentTime:0,duration:(v&&isFinite(v.duration))?v.duration:0};})()
    """

    static let toggle = """
    (function(){var m=[].slice.call(document.querySelectorAll('video,audio'));\
    for(var i=0;i<m.length;i++){var e=m[i];if(e.readyState>0&&e.currentTime>0){\
    if(e.paused){e.play();}else{e.pause();}return true;}}return false;})()
    """

    static let toggleMute = """
    (function(){var m=[].slice.call(document.querySelectorAll('video,audio'));\
    for(var i=0;i<m.length;i++){var e=m[i];if(e.readyState>0&&e.currentTime>0){\
    e.muted=!e.muted;return e.muted;}}return false;})()
    """

    static func seek(_ delta: Double) -> String {
        """
        (function(){var m=[].slice.call(document.querySelectorAll('video,audio'));\
        for(var i=0;i<m.length;i++){var e=m[i];if(e.readyState>0&&e.currentTime>0){\
        e.currentTime=Math.max(0,e.currentTime+(\(Int(delta))));return e.currentTime;}}return 0;})()
        """
    }
}

final class NowPlayingBar: NSView {

    var onTogglePlay: (() -> Void)?
    var onSeekBack: (() -> Void)?
    var onSeekForward: (() -> Void)?
    var onToggleMute: (() -> Void)?
    var onReveal: (() -> Void)?

    private let artwork = NSImageView()
    private let artworkFallback = NSTextField(labelWithString: "♪")
    private let titleLabel = NSTextField(labelWithString: "")
    private let artistLabel = NSTextField(labelWithString: "")
    private let progressTrack = NSView()
    private let progressFill = NSView()
    private let playButton = NSButton()
    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private let muteButton = NSButton()
    private let topLine = NSView()

    private var artworkURL = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.ink.cgColor

        topLine.wantsLayer = true
        topLine.layer?.backgroundColor = Theme.line.cgColor
        addSubview(topLine)

        artwork.wantsLayer = true
        artwork.layer?.cornerRadius = 6
        artwork.layer?.masksToBounds = true
        artwork.imageScaling = .scaleProportionallyUpOrDown
        addSubview(artwork)

        artworkFallback.font = .systemFont(ofSize: 15, weight: .medium)
        artworkFallback.textColor = Theme.mossDeep
        artworkFallback.alignment = .center
        artworkFallback.wantsLayer = true
        artworkFallback.layer?.backgroundColor = Theme.panel.cgColor
        artworkFallback.layer?.cornerRadius = 6
        addSubview(artworkFallback)

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = Theme.cream
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        artistLabel.font = .systemFont(ofSize: 11)
        artistLabel.textColor = Theme.muted
        artistLabel.lineBreakMode = .byTruncatingTail
        addSubview(artistLabel)

        progressTrack.wantsLayer = true
        progressTrack.layer?.backgroundColor = Theme.line.cgColor
        progressTrack.layer?.cornerRadius = 1
        addSubview(progressTrack)

        progressFill.wantsLayer = true
        progressFill.layer?.backgroundColor = Theme.acid.cgColor
        progressFill.layer?.cornerRadius = 1
        progressTrack.addSubview(progressFill)

        configure(backButton, glyph: "↺", action: #selector(handleBack))
        configure(playButton, glyph: "▶", action: #selector(handlePlay))
        configure(forwardButton, glyph: "↻", action: #selector(handleForward))
        configure(muteButton, glyph: "◧", action: #selector(handleMute))
    }

    required init?(coder: NSCoder) { fatalError() }

    private func configure(_ button: NSButton, glyph: String, action: Selector) {
        button.title = glyph
        button.font = .systemFont(ofSize: 13)
        button.isBordered = false
        button.contentTintColor = Theme.bone
        button.target = self
        button.action = action
        addSubview(button)
    }

    @objc private func handlePlay() { onTogglePlay?() }
    @objc private func handleBack() { onSeekBack?() }
    @objc private func handleForward() { onSeekForward?() }
    @objc private func handleMute() { onToggleMute?() }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if titleLabel.frame.insetBy(dx: 0, dy: -8).contains(point) { onReveal?() }
    }

    override func layout() {
        super.layout()
        let height = bounds.height
        topLine.frame = NSRect(x: 0, y: height - 1, width: bounds.width, height: 1)

        let art = NSRect(x: 12, y: (height - 34) / 2, width: 34, height: 34)
        artwork.frame = art
        artworkFallback.frame = art

        let controlsWidth: CGFloat = 4 * 30 + 12
        let textX: CGFloat = 56
        let textWidth = max(80, bounds.width - textX - controlsWidth - 20)

        titleLabel.frame = NSRect(x: textX, y: height / 2 + 1, width: textWidth, height: 15)
        artistLabel.frame = NSRect(x: textX, y: height / 2 - 15, width: textWidth, height: 14)

        progressTrack.frame = NSRect(x: textX, y: 6, width: textWidth, height: 2)

        var x = bounds.width - controlsWidth
        for button in [backButton, playButton, forwardButton, muteButton] {
            button.frame = NSRect(x: x, y: (height - 26) / 2, width: 26, height: 26)
            x += 30
        }
    }

    func apply(_ state: NowPlaying) {
        titleLabel.stringValue = state.title
        artistLabel.stringValue = state.artist
        playButton.title = state.playing ? "❙❙" : "▶"
        playButton.contentTintColor = state.playing ? Theme.acid : Theme.bone
        muteButton.contentTintColor = state.muted ? Theme.warn : Theme.bone
        muteButton.title = state.muted ? "◫" : "◧"

        let fraction = state.duration > 0 ? min(1, max(0, state.position / state.duration)) : 0
        progressFill.frame = NSRect(x: 0, y: 0,
                                    width: progressTrack.bounds.width * fraction,
                                    height: progressTrack.bounds.height)

        if state.artworkURL != artworkURL {
            artworkURL = state.artworkURL
            artwork.image = nil
            artwork.isHidden = true
            artworkFallback.isHidden = false
            guard let url = URL(string: state.artworkURL) else { return }
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let image = NSImage(data: data) else { return }
                DispatchQueue.main.async {
                    guard let self, self.artworkURL == state.artworkURL else { return }
                    self.artwork.image = image
                    self.artwork.isHidden = false
                    self.artworkFallback.isHidden = true
                }
            }.resume()
        }
    }
}
