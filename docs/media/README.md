# Media assets

Every file in this folder is a placeholder. Replace a file, keep its name, and the
README picks it up with no edits.

## Before you capture anything

Run a throwaway profile so none of your history, accounts or bookmarks end up in a
public screenshot:

```sh
FORGE_PROFILE=demo ./scripts/run.sh
```

Set up a few neutral shortcut tiles in that profile and use it for every capture.

- Window size: 1440x900 for full-window shots. Keep it identical across captures.
- Retina: macOS captures at 2x. Downscale to the target width before committing.
- GIFs: 12-15 fps, under 5 MB each. Record with QuickTime (File > New Screen Recording),
  then convert:

```sh
ffmpeg -i in.mov -vf "fps=14,scale=1200:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse" out.gif
```

`brew install gifski` gives smaller files if ffmpeg output is too heavy.

## Asset list

| File | What to capture | Notes |
|---|---|---|
| `hero-banner.png` | The Forge wordmark logo, cat inside the O, on pitch black | 1280x360. Leave breathing room; GitHub crops nothing but it sits above the title |
| `hero-newtab.png` | Whole window on the new tab page | Trays, localhost list and stats all visible in one frame |
| `demo-command-palette.gif` | Press cmd-K, type `json`, hit return, land in the JSON formatter | ~6s. Start with the palette closed so the open animation reads |
| `demo-request-inspector.gif` | Open the sidebar Network section on a news site, let hosts fill in, click Block on a tracker | ~10s. Move the pointer off the row at the end so the lit marker is visible unhovered |
| `demo-audio-path.gif` | Play something on YouTube Music, press opt-cmd-S, scroll the audio panel | ~8s. The spectrum has to be moving or the panel looks static |
| `demo-dev-autoreload.gif` | Terminal and Forge side by side; restart a vite server and let the tab reload itself | ~8s. Show the terminal, or nobody believes the reload was automatic |
| `demo-tab-overflow.gif` | Open ~25 tabs, scroll the strip, open the overflow menu | ~6s. The point is the + button staying reachable |
| `demo-bypass-indicator.gif` | Turn on Ignore Certificate Errors for one tab, then turn it off | ~5s. Orange tab border and the toolbar pill both need to be in frame |
| `shot-stats-video.png` | Video pipeline section of stats for nerds, mid-playback | Best on a 1080p AV1 video so the decoder line shows hardware decode |
| `shot-sidebar-tabs.png` | Sidebar tab manager with two coloured groups and something in the filter | |
| `shot-private-window.png` | Private window on its landing page | The PRIVATE pill in the toolbar should be legible |
| `shot-devservers.png` | The localhost section of the new tab page | Have two or three real servers up; one alone looks accidental |
| `shot-utility-belt.png` | One tool page with real input and output | JWT decoder reads best. Use a token you generated, never a real one |
| `shot-tab-groups.png` | Just the tab strip, cropped, with coloured groups | 1100x300 crop, not a full window |

## Do not capture

- Any tab showing a signed-in account, email address, or private repository
- The AccuWeather widget with your location resolved
- Terminal windows with your home directory path visible, if you'd rather not publish
  your macOS username
