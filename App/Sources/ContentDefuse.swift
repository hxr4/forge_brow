import Foundation

enum ContentDefuse {

    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "forge.defuseYouTube") == nil { return true }
            return UserDefaults.standard.bool(forKey: "forge.defuseYouTube")
        }
        set { UserDefaults.standard.set(newValue, forKey: "forge.defuseYouTube") }
    }

    static let script = """
    (function () {
      if (window.__forgeDefuse) { return; }
      window.__forgeDefuse = 1;
      window.__forgeDefused = 0;

      var host = location.hostname || '';
      if (host.indexOf('youtube.com') < 0 && host.indexOf('youtube-nocookie.com') < 0) { return; }

      var KEYS = ['adPlacements', 'playerAds', 'adSlots', 'adBreakHeartbeatParams',
                  'adServiceSlots', 'adsEngagementPanelRenderer', 'playerAdParams'];

      function strip(node, depth) {
        if (!node || typeof node !== 'object' || depth > 4) { return node; }
        var index;
        for (index = 0; index < KEYS.length; index++) {
          if (Object.prototype.hasOwnProperty.call(node, KEYS[index])) {
            try { delete node[KEYS[index]]; window.__forgeDefused++; } catch (error) {}
          }
        }
        if (Array.isArray(node)) {
          for (index = 0; index < node.length && index < 64; index++) {
            strip(node[index], depth + 1);
          }
          return node;
        }
        if (node.playerResponse) { strip(node.playerResponse, depth + 1); }
        if (node.playerConfig) { strip(node.playerConfig, depth + 1); }
        if (node.response) { strip(node.response, depth + 1); }
        if (node.contents) { strip(node.contents, depth + 1); }
        return node;
      }

      var nativeParse = JSON.parse;
      JSON.parse = function (text, reviver) {
        var value = nativeParse.call(this, text, reviver);
        try { strip(value, 0); } catch (error) {}
        return value;
      };

      if (window.Response && Response.prototype && Response.prototype.json) {
        var nativeJSON = Response.prototype.json;
        Response.prototype.json = function () {
          return nativeJSON.call(this).then(function (value) {
            try { strip(value, 0); } catch (error) {}
            return value;
          });
        };
      }

      var stored;
      try {
        Object.defineProperty(window, 'ytInitialPlayerResponse', {
          configurable: true,
          get: function () { return stored; },
          set: function (value) {
            try { strip(value, 0); } catch (error) {}
            stored = value;
          }
        });
      } catch (error) {}

      function sweep() {
        var player = document.getElementById('movie_player');
        if (player) {
          var showing = player.classList.contains('ad-showing') ||
                        player.classList.contains('ad-interrupting');
          if (showing) {
            var video = player.querySelector('video');
            if (video && isFinite(video.duration) && video.duration > 0) {
              try {
                video.currentTime = video.duration;
                video.play();
                window.__forgeDefused++;
              } catch (error) {}
            }
            var skip = player.querySelector(
              '.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button');
            if (skip) { try { skip.click(); } catch (error) {} }
          }
        }
        var overlay = document.querySelector(
          '.ytp-ad-overlay-close-button, .ytp-ad-overlay-close-container button');
        if (overlay) { try { overlay.click(); } catch (error) {} }
      }

      setInterval(sweep, 400);
      document.addEventListener('DOMContentLoaded', sweep);
    })();
    """
}
