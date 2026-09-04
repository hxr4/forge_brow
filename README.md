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
| Scriptlet injection | **Wired, not effective.** Only 17 resources parse from Brave's library, so scriptlet rules do not fire. |
| Generic cosmetic rules (class/id) | **Not implemented.** Needs renderer-side class/id collection over a message router. |

Consequence: banner ads, trackers and popups are blocked. **YouTube in-stream video ads are
not**, and some sponsored feed cards survive — those need the scriptlet and generic-cosmetic
paths above. Don't treat Forge as a privacy tool until those land.

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

## Safety

Any tab with a bypass active shows a persistent indicator — orange tab border plus a
`⚠︎ CERT CHECKS OFF` pill in the toolbar — for as long as it is active. Bypasses are always
scoped to one tab, never global.

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
