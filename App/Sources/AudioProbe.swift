import Foundation

struct AudioSnapshot {
    var host = ""
    var mime = ""
    var kbps = 0
    var bytes = 0
    var duration: Double = 0
    var position: Double = 0
    var contextRate: Double = 0
    var channels = 0
    var playing = false
    var spectrum: [Double] = []

    init?(_ payload: [String: Any]) {
        guard let host = payload["host"] as? String else { return nil }
        self.host = host
        mime = payload["mime"] as? String ?? ""
        kbps = (payload["kbps"] as? NSNumber)?.intValue ?? 0
        bytes = (payload["bytes"] as? NSNumber)?.intValue ?? 0
        duration = (payload["duration"] as? NSNumber)?.doubleValue ?? 0
        position = (payload["position"] as? NSNumber)?.doubleValue ?? 0
        contextRate = (payload["contextRate"] as? NSNumber)?.doubleValue ?? 0
        channels = (payload["channels"] as? NSNumber)?.intValue ?? 0
        playing = payload["playing"] as? Bool ?? false
        if let bars = payload["spectrum"] as? [NSNumber] {
            spectrum = bars.map { min(1, max(0, $0.doubleValue / 255)) }
        }
    }

    var codecLabel: String {
        guard !mime.isEmpty else { return "—" }
        let lower = mime.lowercased()
        var codec = "—"
        if let range = lower.range(of: "codecs=") {
            codec = String(lower[range.upperBound...])
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "'", with: "")
                .split(separator: ",").first.map(String.init) ?? "—"
        }
        if codec.hasPrefix("opus") { codec = "Opus" }
        else if codec.hasPrefix("mp4a.40.2") { codec = "AAC-LC" }
        else if codec.hasPrefix("mp4a.40.5") { codec = "HE-AAC" }
        else if codec.hasPrefix("mp4a.40.29") { codec = "HE-AACv2" }
        else if codec.hasPrefix("mp4a") { codec = "AAC" }
        else if codec.hasPrefix("vorbis") { codec = "Vorbis" }
        else if codec.hasPrefix("flac") { codec = "FLAC" }
        else if codec.hasPrefix("ac-3") { codec = "AC-3" }
        else if codec.hasPrefix("ec-3") { codec = "E-AC-3" }
        else if codec.hasPrefix("alac") { codec = "ALAC" }

        var container = ""
        if lower.contains("webm") { container = "WebM" }
        else if lower.contains("mp4") { container = "MP4" }
        else if lower.contains("mpeg") { container = "MPEG" }
        else if lower.contains("ogg") { container = "Ogg" }

        return container.isEmpty ? codec : codec + " / " + container
    }

    var nativeRate: Double? {
        let label = codecLabel
        if label.hasPrefix("Opus") { return 48000 }
        if label.hasPrefix("Vorbis") { return 44100 }
        if label.hasPrefix("AAC") || label.hasPrefix("HE-AAC") { return 44100 }
        if label.hasPrefix("FLAC") || label.hasPrefix("ALAC") { return 44100 }
        return nil
    }
}

enum AudioProbeScript {
    static let script = """
    (function () {
      if (window.__forgeAudioHook) { return; }
      window.__forgeAudioHook = 1;

      var mimes = [];
      var audioBytes = 0;
      var videoBytes = 0;
      var lastFrames = 0, lastStamp = 0, framesPerSecond = 0;

      if (window.MediaSource && MediaSource.prototype && MediaSource.prototype.addSourceBuffer) {
        var addBuffer = MediaSource.prototype.addSourceBuffer;
        MediaSource.prototype.addSourceBuffer = function (mime) {
          var buffer = addBuffer.call(this, mime);
          try {
            var isAudio = /audio/i.test(mime);
            mimes.push(mime);
            var append = buffer.appendBuffer.bind(buffer);
            buffer.appendBuffer = function (data) {
              try {
                var size = 0;
                if (data) {
                  if (typeof data.byteLength === 'number') { size = data.byteLength; }
                  else if (data.buffer && typeof data.buffer.byteLength === 'number') { size = data.buffer.byteLength; }
                }
                if (isAudio) { audioBytes += size; } else { videoBytes += size; }
              } catch (error) {}
              return append(data);
            };
          } catch (error) {}
          return buffer;
        };
      }

      var context = null, analyser = null, sourceNode = null, attached = null, bins = null;

      function activeMedia() {
        var list = document.querySelectorAll('video,audio');
        for (var i = 0; i < list.length; i++) {
          var element = list[i];
          if (element.readyState > 0 && element.currentTime > 0 && !element.paused) { return element; }
        }
        return list.length ? list[0] : null;
      }

      function attach(element) {
        if (!element || attached === element) { return; }
        attached = element;
        try {
          if (!context) { context = new (window.AudioContext || window.webkitAudioContext)(); }
          if (context.state === 'suspended') { context.resume(); }
          sourceNode = context.createMediaElementSource(element);
          analyser = context.createAnalyser();
          analyser.fftSize = 128;
          analyser.smoothingTimeConstant = 0.72;
          sourceNode.connect(analyser);
          analyser.connect(context.destination);
          bins = new Uint8Array(analyser.frequencyBinCount);
        } catch (error) {
          analyser = null;
          bins = null;
        }
      }

      window.__forgeAudio = function (withSpectrum) {
        var element = activeMedia();
        if (!element) { return null; }
        if (withSpectrum) { attach(element); }

        var bars = [];
        if (analyser && bins) {
          analyser.getByteFrequencyData(bins);
          var step = Math.floor(bins.length / 28) || 1;
          for (var i = 0; i < 28; i++) {
            var sum = 0, count = 0;
            for (var j = i * step; j < (i + 1) * step && j < bins.length; j++) { sum += bins[j]; count++; }
            bars.push(count ? Math.round(sum / count) : 0);
          }
        }

        var audioMime = '', videoMime = '';
        for (var k = 0; k < mimes.length; k++) {
          if (!audioMime && /audio/i.test(mimes[k])) { audioMime = mimes[k]; }
          if (!videoMime && /video/i.test(mimes[k])) { videoMime = mimes[k]; }
        }

        var played = element.currentTime || 0;
        var appended = played;
        try {
          if (element.buffered && element.buffered.length) {
            appended = element.buffered.end(element.buffered.length - 1);
          }
        } catch (error) {}
        return {
          host: location.hostname,
          mime: audioMime || (mimes.length ? mimes[0] : ''),
          kbps: (appended > 1 && audioBytes) ? Math.round(audioBytes * 8 / appended / 1000) : 0,
          bytes: audioBytes,
          duration: isFinite(element.duration) ? element.duration : 0,
          position: played,
          contextRate: context ? context.sampleRate : 0,
          channels: sourceNode ? sourceNode.channelCount : 0,
          playing: !element.paused,
          spectrum: bars,
          video: (function () {
            var picture = document.querySelector('video');
            if (!picture || !picture.videoWidth) { return null; }
            var quality = picture.getVideoPlaybackQuality
              ? picture.getVideoPlaybackQuality() : null;
            if (quality) {
              var stamp = performance.now();
              if (lastStamp) {
                var elapsed = (stamp - lastStamp) / 1000;
                if (elapsed > 0.35) {
                  framesPerSecond = Math.round((quality.totalVideoFrames - lastFrames) / elapsed);
                  lastFrames = quality.totalVideoFrames;
                  lastStamp = stamp;
                }
              } else {
                lastFrames = quality.totalVideoFrames;
                lastStamp = stamp;
              }
            }
            var hdr = false;
            try { hdr = window.matchMedia('(dynamic-range: high)').matches; } catch (error) {}
            return {
              mime: videoMime,
              width: picture.videoWidth,
              height: picture.videoHeight,
              kbps: (appended > 1 && videoBytes) ? Math.round(videoBytes * 8 / appended / 1000) : 0,
              fps: framesPerSecond,
              dropped: quality ? quality.droppedVideoFrames : 0,
              totalFrames: quality ? quality.totalVideoFrames : 0,
              displayHDR: hdr
            };
          })()
        };
      };
    })();
    """

    static let call = "(window.__forgeAudio ? window.__forgeAudio(true) : null)"
}

struct VideoSnapshot {
    var mime = ""
    var width = 0
    var height = 0
    var kbps = 0
    var fps = 0
    var dropped = 0
    var totalFrames = 0
    var displayHDR = false

    init?(_ payload: [String: Any]?) {
        guard let payload else { return nil }
        mime = payload["mime"] as? String ?? ""
        width = (payload["width"] as? NSNumber)?.intValue ?? 0
        height = (payload["height"] as? NSNumber)?.intValue ?? 0
        kbps = (payload["kbps"] as? NSNumber)?.intValue ?? 0
        fps = (payload["fps"] as? NSNumber)?.intValue ?? 0
        dropped = (payload["dropped"] as? NSNumber)?.intValue ?? 0
        totalFrames = (payload["totalFrames"] as? NSNumber)?.intValue ?? 0
        displayHDR = payload["displayHDR"] as? Bool ?? false
        guard width > 0 else { return nil }
    }

    private var codecToken: String {
        let lower = mime.lowercased()
        guard let range = lower.range(of: "codecs=") else { return "" }
        return String(lower[range.upperBound...])
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
            .split(separator: ",").first.map(String.init) ?? ""
    }

    var codecLabel: String {
        let token = codecToken
        guard !token.isEmpty else { return "—" }
        var name = token
        if token.hasPrefix("vp09") || token.hasPrefix("vp9") { name = "VP9" }
        else if token.hasPrefix("vp08") || token.hasPrefix("vp8") { name = "VP8" }
        else if token.hasPrefix("av01") { name = "AV1" }
        else if token.hasPrefix("avc1") || token.hasPrefix("avc3") { name = "H.264" }
        else if token.hasPrefix("hvc1") || token.hasPrefix("hev1") { name = "HEVC" }

        var container = ""
        let lower = mime.lowercased()
        if lower.contains("webm") { container = "WebM" }
        else if lower.contains("mp4") { container = "MP4" }
        return container.isEmpty ? name : name + " / " + container
    }

    var depthLabel: String {
        let token = codecToken
        let parts = token.split(separator: ".")
        if token.hasPrefix("vp09"), parts.count > 3, let depth = Int(parts[3]) {
            return "\(depth)-bit"
        }
        if token.hasPrefix("av01"), parts.count > 3 {
            let tail = String(parts[3])
            if tail.hasPrefix("10") { return "10-bit" }
            if tail.hasPrefix("08") { return "8-bit" }
        }
        if token.hasPrefix("avc1") { return "8-bit" }
        return "—"
    }

    var resolutionLabel: String {
        guard width > 0, height > 0 else { return "—" }
        let tag: String
        switch height {
        case 2160...: tag = " · 4K"
        case 1440..<2160: tag = " · 1440p"
        case 1080..<1440: tag = " · 1080p"
        case 720..<1080: tag = " · 720p"
        default: tag = ""
        }
        return "\(width)×\(height)" + tag
    }
}
