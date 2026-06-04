# yasb-wallpaper-engine-color-sync

Automatically tint your [YASB](https://github.com/amnweb/yasb) status bar(s) to match
your active [Wallpaper Engine](https://www.wallpaperengine.io/) wallpaper.

Change your wallpaper, and your bar re-colors to match — instantly. Because every YASB
bar shares one `styles.css`, your **top and bottom bars stay perfectly in sync** with no
extra work. It can also re-tint the **Windows taskbar** to match, via
[TranslucentTB](#matching-the-windows-taskbar-translucenttb).

![demo placeholder](docs/demo.gif)

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

- Windows
- [YASB](https://github.com/amnweb/yasb) (`winget install AmN.yasb`)
- [Wallpaper Engine](https://store.steampowered.com/app/431960/Wallpaper_Engine/) (Steam)
- Windows PowerShell 5.1+ (built in) — no extra modules
- **Only if you want the matching taskbar:** [TranslucentTB](https://github.com/TranslucentTB/TranslucentTB)
  (`winget install CharlesMilette.TranslucentTB`) — **you must set its `desktop_appearance.accent`
  to `opaque` once** for the tool to drive the color. See [Matching the Windows taskbar](#matching-the-windows-taskbar-translucenttb).

## Setup

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

3. **Run it once** to verify:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\yasb-wallpaper-engine-color-sync.ps1 -Once -Verbose
   ```

4. **Run it for real** (watches until you close it):

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\yasb-wallpaper-engine-color-sync.ps1
   ```

## Run at login (hidden)

Drop [`start-hidden.vbs`](start-hidden.vbs) (edit the path inside) into your Startup folder
(`shell:startup`). It launches the watcher with no console window.

## Options

| Parameter          | Default                                                                 | Description |
|--------------------|-------------------------------------------------------------------------|-------------|
| `-WeConfig`        | `C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine\config.json` | Wallpaper Engine `config.json` |
| `-User`            | *(auto-detected)*                                                       | Top-level user key inside the WE config |
| `-StylesPath`      | `%USERPROFILE%\.config\yasb\styles.css`                                 | Your YASB stylesheet |
| `-Lightness`       | `0.32`                                                                  | Target lightness (0–1) the bar color is normalized to (keeps white text readable) |
| `-Saturation`      | `0.6`                                                                   | Minimum saturation (0–1), applied only to colors with real chroma (see `-ChromaThreshold`); `0` keeps everything muted |
| `-ChromaThreshold` | `0.10`                                                                  | Only boost saturation when the color is clearly colored — near-grays stay muted instead of being tinted a hue |
| `-BlackThreshold`  | `12`                                                                    | Scheme colors darker than this (channel sum /765) are treated as unset → sample |
| `-WriteBackToWallpaperEngine` | `$true`                                                      | Write the sampled color back into WE's scheme color (fills blank `0 0 0`) |
| `-TranslucentTBSettings` | *(Store install path)*                                            | TranslucentTB `settings.json` — when it exists, the **taskbar** is re-tinted to match the bar |
| `-SetWindowsAccent` | `$false`                                                               | Set the Windows accent (title bars). Off because it can't reliably color the Win11 taskbar and makes tiling WMs re-tile windows |
| `-BackgroundAlpha` | `235`                                                                   | Bar background opacity, 0–255 |
| `-Once`            | *(off)*                                                                 | Apply once and exit instead of watching |

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

Add a Startup shortcut for TranslucentTB (and the watcher) so it all comes back at login.

### A note on the Windows accent (`-SetWindowsAccent`, off by default)

Setting the Windows accent colors your **title bars** to match, but it does **not** reliably
color the Win11 taskbar (see above), and applying it — toggling `ColorPrevalence` and
broadcasting `ImmersiveColorSet` — makes tiling WMs like **komorebi re-tile every window** on
each change. It's off by default for that reason; enable it only if you want the title-bar
tint and don't mind the re-tile.

## Notes

- Multi-monitor wallpapers: the color is taken from `Monitor0`. Per-monitor tinting is a
  possible future enhancement.
- Want it on komorebi-bar instead of YASB? See the sibling project:
  [komorebi-bar-wallpaper-engine-color-sync](https://github.com/brendanwelsh/komorebi-bar-wallpaper-engine-color-sync).

## License

MIT — see [LICENSE](LICENSE).
