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
3. **Sampled dominant color** — averaged from the wallpaper's `preview` image, ignoring
   near-black/near-white pixels (fallback when no scheme color exists).

The chosen color is darkened (configurable) so white bar text stays legible, then written
between the `WP-SYNC` markers in `styles.css`. **Everything outside those markers is
yours** — fonts, spacing, widget layout, the workspace bubble shape, etc.

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
| `-Darken`          | `0.55`                                                                  | 0–1 multiplier; lower = darker (keeps white text readable) |
| `-BackgroundAlpha` | `235`                                                                   | Bar background opacity, 0–255 |
| `-Once`            | *(off)*                                                                 | Apply once and exit instead of watching |

## Notes

- Multi-monitor wallpapers: the color is taken from `Monitor0`. Per-monitor tinting is a
  possible future enhancement.
- Want it on komorebi-bar instead of YASB? See the sibling project:
  [komorebi-bar-wallpaper-engine-color-sync](https://github.com/brendanwelsh/komorebi-bar-wallpaper-engine-color-sync).

## License

MIT — see [LICENSE](LICENSE).
