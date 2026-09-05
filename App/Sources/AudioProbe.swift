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
                if (isAudio) { audioBytes += size; }
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

        var audioMime = '';
        for (var k = 0; k < mimes.length; k++) {
          if (/audio/i.test(mimes[k])) { audioMime = mimes[k]; break; }
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
          spectrum: bars
        };
      };
    })();
    """

    static let call = "(window.__forgeAudio ? window.__forgeAudio(true) : null)"
}
