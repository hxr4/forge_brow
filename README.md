# Forge

A development-first macOS browser built on Chromium via CEF.

Personal tool, built for one developer's daily use. Open source so anyone can use it,
but nothing here is designed around a general audience.

**Status: alpha, in daily use.** Verified on macOS 26 / Apple Silicon with
CEF 144.0.34 (Chromium 144.0.7559.261).

## Why this exists

Every mainstream browser treats development as a panel you open with a keystroke and
close again. Forge makes it the chrome:

- **Your running localhost services are on the new tab page** — port, process, one click to open.
  No other browser knows or cares that you have a dev server up.
- **Thirteen utilities that run locally** — JSON, JWT, Base64, hashing, regex, timestamps,
  URL tools, SQL, colour, gradients, shadows, JSON→TypeScript. No network, no extension
  permissions. You stop pasting production tokens into strangers' websites.
- **Per-tab security bypasses that cannot be silently left on** — ignoring certificate errors
  is scoped to one tab and paints it orange until you turn it off.
- **One command palette over everything** — tabs, tools, ports, history, settings.

## Requirements

- Apple Silicon Mac, macOS 13+
- Xcode with command line tools
- Homebrew

## Build

```sh
./scripts/bootstrap.sh     # cmake, ninja, xcodegen, rust, CEF, filter lists
./scripts/build.sh         # generates the Xcode project and builds
./scripts/run.sh           # launches the built app
```

`bootstrap.sh` downloads the CEF binary distribution (~265 MB) into `third_party/`,
which is gitignored. The first build compiles `libcef_dll_wrapper` from source and takes
a few minutes.

Build through `scripts/build.sh`, not Xcode's Run button — bundle assembly (framework,
five helper processes, signing) happens after `xcodebuild`, for reasons in *Build notes*.

## Content blocking — what actually works

Honest accounting, because a blocked-request counter on its own is misleading.

| Layer | State |
|---|---|
| Network filtering (requests cancelled) | **Working.** 205k+ rules from 8 lists. |
| Popup blocking | **Working.** Non-gesture popups blocked; `target=_blank` becomes a tab. |
| Cosmetic filtering, domain-specific | **Working.** Element-hiding CSS injected per page. |
| YouTube video ads | **Working.** First-party module, see below. |
| Generic scriptlet rules (`##+js(...)`) | **Not implemented.** See below. |
| Generic cosmetic rules (class/id) | **Not implemented.** Needs renderer-side class/id collection. |

### YouTube

In-stream ads cannot be blocked at the network layer: they come from the same
googlevideo.com hosts as the video, described in the same player response. uBlock Origin
strips them with scriptlets that prune the ad slots before the player reads them.

Forge cannot run those scriptlets. adblock-rust's resource assembler parses only uBlock's
*old* scriptlet format — its own documentation says the current format is an ES module and
recommends converting it in JS — and the resource file Brave publishes at the obvious URL
holds 17 Brave-specific scripts, not the scriptlet library. That is why earlier builds
reported zero bytes of scriptlet on every page.

So Forge ships its own module instead, injected at document start over the DevTools
protocol. It arms only on YouTube, wraps `JSON.parse` and `Response.prototype.json`, and
defines a setter for `ytInitialPlayerResponse`, deleting `adPlacements`, `playerAds`,
`adSlots` and siblings before the player sees them. A sweep skips and dismisses anything
that starts anyway. Every deletion is counted and shown in stats for nerds.

Verified against a signed-out profile — no Premium — on heavily monetised videos: content
starts immediately with no pre-roll.

This is one site handled deliberately, not a scriptlet engine. Filter-list `##+js()` rules
still do not run.

Lists: EasyList, EasyPrivacy, uBlock Origin (filters, privacy, quick-fixes, badware,
annoyances-cookies), Fanboy annoyances.

## Architecture

```
App/Sources         Swift  — window, tabs, palette, menus, history, bookmarks
native/ForgeCEF     ObjC++ — shim over the CEF C++ API, exposes plain ObjC to Swift
native/shared       C++    — scheme registration shared by app and helper
helper/             ObjC++ — CEF helper process entry point (sandboxed)
rust/forge-adblock  Rust   — C ABI over adblock-rust, static library
App/Resources/web   HTML   — landing page, settings, history, tools, served over forge://
```

Swift never sees a C++ type. Everything crossing the boundary is plain Objective-C, which
is what the bridging header imports.

Pages talk to the app over the custom `forge://` scheme rather than a JS bridge:
`GET forge://home/api/state` returns app state, `POST forge://home/api/command` dispatches
an action. No renderer-side code needed.

Internal pages: `forge://settings`, `forge://history`, `forge://bookmarks`,
`forge://downloads`, `forge://tools`, `forge://help`.

`GET /api/state` includes a `revision` integer that only changes when the content behind
it changes. Poll it and skip re-rendering when it has not moved — the state is otherwise
identical between polls and re-rendering it is what made static content look like it was
reloading.

`POST /api/command` actions for the landing page shortcuts:

| action | payload | effect |
| --- | --- | --- |
| `addShortcut` | `title`, `url`, `tray` (optional) | add a tile; first tray if `tray` is omitted |
| `removeShortcut` | `url`, `tray` (optional) | remove from one tray, or all when omitted |
| `moveShortcut` | `tray`, `url`, `index` | reorder within a tray |
| `renameShortcut` | `tray`, `url`, `title` | rename a tile |
| `addTray` / `removeTray` | `name` | add or remove a tray; the last tray cannot be removed |
| `renameTray` | `from`, `to` | rename a tray |

Adding is a no-op for a URL already in the tray. Every one of these bumps `revision`.

### Asking a page a question

`FGBrowserView -evaluate:completion:` runs JavaScript in a tab and returns the value, built
on `ExecuteDevToolsMethod("Runtime.evaluate")` plus a `CefDevToolsMessageObserver`. It needs
no DevTools front-end and no renderer-side code. The now playing bar and the stats overlay
are both built on it, and it is the general-purpose hook for anything that needs to read
page state from Swift.

## Browser features

- **Tabs** — horizontal or vertical strip, site favicons with an on-disk cache, and
  collapsible coloured groups that keep their members contiguous.
- **Omnibox** — history and bookmark matches merged with live completions from the active
  engine. Remote completions are debounced, cookie-free and switchable off; local matches
  keep working without them.
- **Now playing** — a bar appears while any tab plays audio, with artwork, title, artist and
  progress from `mediaSession`, play/pause, ±10s, mute, and click-to-jump-to-the-noisy-tab.
- **Stats for nerds** — ⌥⌘S, or View › Developer. Per-page DOM, request, transfer and timing
  figures alongside blocked counts, filter rule count, helper process count and browser
  memory.
- **Audio path** — when something is playing, the same panel shows the whole signal chain:
  codec and container read from the MediaSource buffer, bitrate measured from appended
  bytes, channel count, the browser's mix rate, then your actual output device, its sample
  rate, physical bit depth and transport, and whether the system is resampling between the
  codec's rate and the device's. With a live spectrum. Works on any site that streams over
  MSE.
- **Profiles** — `FORGE_PROFILE=name` runs an independent session, so a signed-out or
  throwaway instance is one environment variable away.
- **Shortcuts** — editable trays, from the Bookmarks menu, the palette, or the page API.
- **Default browser** — Forge declares `http`/`https` and opens URLs handed to it by other
  applications.

## Safety

Any tab with a bypass active shows a persistent indicator — orange tab border plus a
`⚠︎ CERT CHECKS OFF` pill in the toolbar — for as long as it is active. Bypasses are always
scoped to one tab, never global.

Group colours never use amber, and a tab with an active bypass suppresses its group accent,
so amber in the tab strip only ever means a bypass is on.

Forge declares usage descriptions for every capability it hands to web content — Bluetooth,
camera, microphone, location, speech, local network, user folders. macOS aborts any process
that touches one of these without a declared purpose, which is what used to kill the browser
the moment a sign-in page offered a passkey.

Renderer processes run inside the Chromium sandbox.

## Build notes

Four things about CEF on modern macOS that cost real time:

**`cef_sandbox.a` no longer exists.** As of CEF 144 the sandbox is exported as a C API from
the framework itself, and `CefScopedSandboxContext` lives in `libcef_dll_wrapper`. The helper
links only `-lcef_dll_wrapper` — no `-lcef_sandbox`, no `-lsandbox`. The sandbox is on.

**Xcode's `Validate` step rejects the CEF framework.** CEF ships a flat, unversioned framework
whose `Info.plist` sits at `Resources/Info.plist`, which `builtin-validationUtility` does not
recognise, and `VALIDATE_PRODUCT=NO` does not disable the step. Bundle assembly therefore runs
*after* `xcodebuild`, from `scripts/build.sh`, so Xcode never sees the framework.

**`CefWindowInfo` on macOS has only `SetAsChild` and `SetAsWindowless`.** There is no
`SetAsPopup`. For DevTools, pass a default-constructed `CefWindowInfo`.

**`DoClose` must return `true` for tab browsers.** Returning `false` makes CEF send a close
notification to the *top-level window*, so closing one tab closes the window — and with
`applicationShouldTerminateAfterLastWindowClosed`, quits the app.

## Configuration

Copy `config/forge.env.example` to `config/forge.env`. That file is gitignored. No keys are
committed.

## Open decisions

- Third search engine slot is unimplemented pending a decision. DuckDuckGo and Brave Search
  are wired up.
- Weather on the landing page needs an AccuWeather key.
- Profiles and private windows are not built; the menu deliberately omits them rather than
  showing entries that do nothing.

## Estimated metrics

"Bandwidth saved" and "time saved" are **estimates** derived from per-resource-type averages,
and are labelled as such in the UI. Blocked-request and popup counts are exact.

## License

MIT
