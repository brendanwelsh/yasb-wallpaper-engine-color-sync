# yasb-wallpaper-engine-color-sync

Automatically tint your [YASB](https://github.com/amnweb/yasb) status bar(s) to match
your active [Wallpaper Engine](https://www.wallpaperengine.io/) wallpaper.

Change your wallpaper, and your bar re-colors to match — instantly. Because every YASB
bar shares one `styles.css`, your **top and bottom bars stay perfectly in sync** with no
extra work.

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
| `-Saturation`      | `0.55`                                                                  | Minimum saturation (0–1); boosts washed-out colors |
| `-BlackThreshold`  | `12`                                                                    | Scheme colors darker than this (channel sum /765) are treated as unset → sample |
| `-WriteBackToWallpaperEngine` | `$true`                                                      | Write the sampled color back into WE's scheme color (fills blank `0 0 0`) |
| `-BackgroundAlpha` | `235`                                                                   | Bar background opacity, 0–255 |
| `-Once`            | *(off)*                                                                 | Apply once and exit instead of watching |

## Notes

- Multi-monitor wallpapers: the color is taken from `Monitor0`. Per-monitor tinting is a
  possible future enhancement.
- Want it on komorebi-bar instead of YASB? See the sibling project:
  [komorebi-bar-wallpaper-engine-color-sync](https://github.com/brendanwelsh/komorebi-bar-wallpaper-engine-color-sync).

## License

MIT — see [LICENSE](LICENSE).
