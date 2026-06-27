# yasb-wallpaper-engine-color-sync

Automatically tint your [YASB](https://github.com/amnweb/yasb) status bar(s) to match
your active [Wallpaper Engine](https://www.wallpaperengine.io/) wallpaper.

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![Platform: Windows](https://img.shields.io/badge/platform-Windows-0078D6)
![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE)

Change your wallpaper, and your bar re-colors to match — in about a second. Because every
YASB bar shares one `styles.css`, your **top and bottom bars stay perfectly in sync** with
no extra work. It can also re-tint the **Windows taskbar** to match, via
[TranslucentTB](#matching-the-windows-taskbar-translucenttb).

<!-- Replace docs/demo.gif with a real screen capture: switch wallpapers in Wallpaper Engine
     and show the bar (and taskbar) re-tinting within ~1s. -->
![Demo: the YASB bar re-tinting to match a Wallpaper Engine wallpaper](docs/demo.gif)

## Features

- 🎨 **Automatic** — switch wallpaper, the bar follows. No clicking, no manual hex codes.
- 🧭 **Smart color pick** — saved scheme color → wallpaper default → saturation-weighted
  sample of the preview image, then HSL-normalized so white text stays legible.
- 🪟 **One file, all bars** — every YASB bar shares `styles.css`, so top/bottom bars match.
- 🧱 **Non-destructive** — only edits a marked `WP-SYNC` block; the rest of your stylesheet
  is yours.
- 🟩 **Taskbar too** *(optional)* — drives [TranslucentTB](#matching-the-windows-taskbar-translucenttb)
  so the Windows taskbar tracks the wallpaper alongside the bar.
- 🟦 **No bar? Still works** *(optional)* — drive the **PowerToys FancyZones** zone-highlight
  color (`-SetFancyZonesColor`) and the **Windows accent** (`-SetWindowsAccent`) from the same
  wallpaper color. Lets a bar-less setup (e.g. FancyZones instead of komorebi+YASB) still tint.
- ⚡ **Idle-cheap** — event-driven via `FileSystemWatcher`; no polling, ~0% CPU at rest.

## How it works

A small PowerShell script watches Wallpaper Engine's `config.json` (event-driven via
`FileSystemWatcher` — no polling, ~0% idle CPU). When the active wallpaper changes, it
resolves a representative color and writes it into a managed block in your YASB
`styles.css`. YASB's `watch_stylesheet: true` then hot-reloads and the bar re-tints.

Color is resolved in priority order:

1. **Saved scheme color** — the color you picked for this wallpaper in Wallpaper Engine
   (`wproperties[file].Monitor0.schemecolor`).
2. **Wallpaper default** — the author's default `schemecolor` from the wallpaper's
   `project.json`.
3. **Sampled dominant color** — from the wallpaper's `preview` image, weighting pixels by
   saturation (so vivid colors win and washed-out sky/gray is ignored). A scheme color of
   `0 0 0` is treated as *unset* and falls through to sampling.

The chosen color is HSL-normalized (consistent lightness + minimum saturation) for a clean,
legible result, then written between the `WP-SYNC` markers in `styles.css` — bar background
plus a lighter **active-workspace bubble**. **Everything outside those markers is yours** —
fonts, spacing, widget layout, the bubble shape, etc.

### Write-back to Wallpaper Engine

When the color comes from sampling (i.e. the wallpaper had no real scheme color), the tool
also writes that color back into Wallpaper Engine's per-wallpaper scheme color, so WE's own
theming matches your bar and the blank `0 0 0` wallpapers get filled in. This is on by
default (`-WriteBackToWallpaperEngine`); it makes a one-time backup of WE's `config.json`
and sanity-checks the edit before writing. Note: Wallpaper Engine may need a restart to
apply the new scheme color to its *own* theming.

## Requirements

- Windows + Windows PowerShell 5.1 (built in) or PowerShell 7 — no extra modules
- [YASB](https://github.com/amnweb/yasb) (`winget install AmN.yasb`)
- [Wallpaper Engine](https://store.steampowered.com/app/431960/Wallpaper_Engine/) (Steam)
- **Only if you want the matching taskbar:** [TranslucentTB](https://github.com/TranslucentTB/TranslucentTB)
  (`winget install CharlesMilette.TranslucentTB`) — and set its `desktop_appearance.accent`
  to `opaque` once (see [Matching the Windows taskbar](#matching-the-windows-taskbar-translucenttb)).

## Install

```powershell
git clone https://github.com/brendanwelsh/yasb-wallpaper-engine-color-sync
cd yasb-wallpaper-engine-color-sync
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

`install.ps1` registers the watcher to start hidden at every login (a shortcut in your
Startup folder, pointed at this repo automatically) and starts it for the current session.
Switch wallpapers and watch the bar follow. Re-running is safe.

- Register for login **without** starting it now: `install.ps1 -NoStart`
- Prefer to do it by hand, or just try it first? See [Setup](#setup) and
  [Run at login](#run-at-login-hidden) below.

## Setup

`install.ps1` handles the login shortcut, but you still need YASB itself wired up:

1. **Enable hot-reload** in `~/.config/yasb/config.yaml`:

   ```yaml
   watch_stylesheet: true
   ```

2. **Add the managed block** to the bottom of your `~/.config/yasb/styles.css`
   (see [`examples/styles.css`](examples/styles.css) for a full stylesheet, including an
   active-workspace "bubble" that tracks the wallpaper):

   ```css
   /* WP-SYNC:START  -- managed by yasb-wallpaper-engine-color-sync; edit shape/text outside this block */
   .yasb-bar { background-color: rgba(41, 42, 41, 0.92); }
   .komorebi-workspaces .ws-btn.active { background-color: #3a5a78; }
   /* WP-SYNC:END */
   ```

   (If you skip this, the script appends the block automatically on first run.)

## Usage

Run it once to verify (writes the color, prints what it did, exits):

```powershell
powershell -ExecutionPolicy Bypass -File .\yasb-wallpaper-engine-color-sync.ps1 -Once -Verbose
```

Run it as a watcher (stays up, re-tints on every wallpaper change; Ctrl+C to stop):

```powershell
powershell -ExecutionPolicy Bypass -File .\yasb-wallpaper-engine-color-sync.ps1
```

## Run at login (hidden)

`install.ps1` already does this. To set it up by hand instead, edit the `SCRIPT` path inside
[`start-hidden.vbs`](start-hidden.vbs) to point at `yasb-wallpaper-engine-color-sync.ps1` on
your machine, then drop a shortcut to the `.vbs` into your Startup folder (`Win+R` →
`shell:startup`). It launches the watcher with no console window.

## Options

| Parameter          | Default                                                                 | Description |
|--------------------|-------------------------------------------------------------------------|-------------|
| `-WeConfig`        | `…\Steam\steamapps\common\wallpaper_engine\config.json`                 | Wallpaper Engine `config.json`. Override if Steam is on another drive/library |
| `-User`            | *(auto-detected)*                                                       | Top-level user key inside the WE config |
| `-StylesPath`      | `%USERPROFILE%\.config\yasb\styles.css`                                 | Your YASB stylesheet |
| `-Lightness`       | `0.32`                                                                  | Target lightness (0–1) the bar color is normalized to (keeps white text readable) |
| `-Saturation`      | `0.6`                                                                   | Minimum saturation (0–1), applied only to colors with real chroma (see `-ChromaThreshold`); `0` keeps everything muted |
| `-ChromaThreshold` | `0.10`                                                                  | Only boost saturation when the color is clearly colored — near-grays stay muted instead of being tinted a hue |
| `-BlackThreshold`  | `12`                                                                    | Scheme colors darker than this (channel sum /765) are treated as unset → sample |
| `-WriteBackToWallpaperEngine` | `$true`                                                      | Write the sampled color back into WE's scheme color (fills blank `0 0 0`) |
| `-TranslucentTBSettings` | *(Store install path)*                                            | TranslucentTB `settings.json` — when it exists, the **taskbar** is re-tinted to match the bar |
| `-SetWindowsAccent` | `$false`                                                               | Set the Windows accent (title bars / Start). Off by default because it can't reliably color the Win11 taskbar and makes tiling WMs re-tile windows; safe to enable if you don't run a tiling WM |
| `-SetYasbColor`    | `$true`                                                                | Write the YASB `styles.css` block (the original target). Pass `-SetYasbColor:$false` if you no longer run YASB |
| `-SetFancyZonesColor` | `$false`                                                            | Drive PowerToys FancyZones' zone-highlight color from the accent (shows while dragging a window over a zone). FancyZones hot-reloads `settings.json` |
| `-FancyZonesSettings` | *(PowerToys default path)*                                          | FancyZones `settings.json` location (only used with `-SetFancyZonesColor`) |
| `-BackgroundAlpha` | `235`                                                                   | Bar background opacity, 0–255 |
| `-Once`            | *(off)*                                                                 | Apply once and exit instead of watching |
| `-LogFile`         | `%USERPROFILE%\.config\yasb\wp-color-sync.log`                          | Where the run log is written |

## Matching the Windows taskbar (TranslucentTB)

Windows 11 won't reliably let you color the taskbar itself: it's translucent (so it mostly
just shows the wallpaper *through* it), and Windows resets any accent value you write. The
robust fix is [TranslucentTB](https://github.com/TranslucentTB/TranslucentTB) (free, Microsoft
Store), which **owns** the taskbar background so the color actually holds.

1. Install + run it once: `winget install CharlesMilette.TranslucentTB`
2. In its `settings.json`
   (`%LOCALAPPDATA%\Packages\28017CharlesMilette.TranslucentTB_*\RoamingState\settings.json`),
   set the desktop appearance to a solid color:

   ```jsonc
   "desktop_appearance": { "accent": "opaque", "color": "#5B8321FF", ... }
   ```
   > TranslucentTB colors are **`#RRGGBBAA`** — alpha is **last**, not first.

3. That's it — this script (via `-TranslucentTBSettings`, which defaults to the Store path)
   rewrites `desktop_appearance.color` to the bar's color on every wallpaper change, and
   TranslucentTB hot-reloads. So the **taskbar tracks the wallpaper right alongside the bar**.

Add a Startup shortcut for TranslucentTB so it comes back at login too.

### A note on the Windows accent (`-SetWindowsAccent`, off by default)

Setting the Windows accent colors your **title bars** to match, but it does **not** reliably
color the Win11 taskbar (see above), and applying it — toggling `ColorPrevalence` and
broadcasting `ImmersiveColorSet` — makes tiling WMs like **komorebi re-tile every window** on
each change. It's off by default for that reason; enable it only if you want the title-bar
tint and don't mind the re-tile.

## Troubleshooting

| Symptom | Fix |
|---|---|
| **Bar color never changes** | Make sure `watch_stylesheet: true` is in `config.yaml`, the `WP-SYNC` block exists in `styles.css`, and run `…ps1 -Once -Verbose` to see what it did. Check the log at `%USERPROFILE%\.config\yasb\wp-color-sync.log`. |
| **"styles.css not found" / wrong path** | Pass `-StylesPath` to point at your actual stylesheet. |
| **"config.json not found"** | Steam is probably on another drive/library — pass `-WeConfig "D:\SteamLibrary\steamapps\common\wallpaper_engine\config.json"`. |
| **Color looks muddy or wrong** | That wallpaper has no scheme color, so it's being sampled. Set a scheme color for it in Wallpaper Engine (it takes priority), or tune `-Saturation` / `-Lightness`. |
| **A plain/gray wallpaper got tinted a weird hue** | Raise `-ChromaThreshold` so near-grays are left muted instead of pushed toward a color. |
| **Taskbar isn't matching** | TranslucentTB must be installed, running, and have `desktop_appearance.accent` set to `opaque`. Confirm the path in `-TranslucentTBSettings` exists. |
| **Nothing happens at login** | Re-run `install.ps1`, confirm the shortcut is in `shell:startup`, and check the log. The watcher starts hidden, so there's no window — the log is how you confirm it's alive. |
| **"running scripts is disabled on this system"** | Launch with `-ExecutionPolicy Bypass` (as shown above); the script itself isn't installed into your policy. |
| **I don't use komorebi** | The bar background still tints. The second managed line targets komorebi's workspace bubble (`.komorebi-workspaces .ws-btn.active`); with no komorebi widget it's just a harmless no-op. |

## Notes & limitations

- **Multi-monitor:** the color is taken from `Monitor0`. Per-monitor tinting is a possible
  future enhancement.
- **Active-workspace accent** targets komorebi's workspace widget. The bar background works
  for any YASB setup; the accent "bubble" only shows if you use that widget.
- **Wallpaper Engine's own theming** may need a WE restart to pick up a written-back scheme
  color (the bar/taskbar update immediately regardless).

## License

MIT — see [LICENSE](LICENSE).
