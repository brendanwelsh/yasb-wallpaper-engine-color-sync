# yasb-wallpaper-engine-color-sync - context

## What & why
A single-file PowerShell tool that automatically tints your YASB status bar(s) — and
optionally the Windows taskbar — to match whatever Wallpaper Engine wallpaper is active.
Change the wallpaper, the bar re-colors instantly. Because every YASB bar shares one
`styles.css`, top and bottom bars stay in sync for free. It only edits a marked managed
block, so the rest of your stylesheet is untouched.

## Where it fits
A desktop-customization glue script for Windows running YASB + Wallpaper Engine (and
optionally TranslucentTB for the taskbar, komorebi as the tiling WM). It reads Wallpaper
Engine's `config.json`, writes into YASB's `styles.css` (hot-reloaded via
`watch_stylesheet: true`), and optionally writes TranslucentTB's `settings.json` and the
Windows accent registry keys. A sibling project does the same for komorebi-bar.

## Run / build / test
No build/deps — Windows PowerShell 5.1+ and `System.Drawing` (built in).
- Apply once: `powershell -ExecutionPolicy Bypass -File .\yasb-wallpaper-engine-color-sync.ps1 -Once -Verbose`
- Watch (default): `powershell -ExecutionPolicy Bypass -File .\yasb-wallpaper-engine-color-sync.ps1`
- Run hidden at login: edit the path in `start-hidden.vbs`, put a shortcut in `shell:startup`.
- No automated test suite; verify by running `-Once -Verbose` and checking the WP-SYNC
  block in `styles.css` plus the log at `%USERPROFILE%\.config\yasb\wp-color-sync.log`.

## Layout & key files
- `yasb-wallpaper-engine-color-sync.ps1` — the whole tool. Key functions:
  `Get-ActiveWallpaper` / `Get-ProjectScheme` (read WE config), `Get-DominantHex`
  (saturation-weighted preview sampling), `Convert-ToVibrant` (HSL normalize),
  `Set-YasbColor` (atomic write of the WP-SYNC block), `Set-TaskbarColor` (TranslucentTB),
  `Set-WindowsAccent`, `Write-WeSchemeColor` (write-back), `Update-Color` (main loop body),
  bottom `while` loop drives a `FileSystemWatcher` on WE's config.
- `examples/styles.css`, `examples/config.yaml` — reference YASB stylesheet (with the
  managed WP-SYNC block + active-workspace "bubble") and config.
- `start-hidden.vbs` — console-less launcher for Startup.
- `README.md` — full user docs and the options table. `LICENSE` — MIT.

## Gotchas
- Color resolution order: saved WE scheme color -> wallpaper `project.json` default ->
  sampled preview dominant color. `0 0 0` scheme = unset, falls through to sampling.
- Only the text between `WP-SYNC:START` / `WP-SYNC:END` markers is managed; everything
  else in `styles.css` is the user's. The block is appended on first run if absent.
- Files are read/written as BOM-free UTF-8; PS 5.1 `Get-Content -Raw` defaults to ANSI,
  which garbled non-ASCII and could balloon the file — keep reads/writes UTF-8.
- `Set-YasbColor` writes atomically (temp + copy) and bails on empty/huge files so YASB
  never reads a half-written stylesheet.
- Write-back to WE backs up `config.json` once and sanity-checks the re-serialized JSON
  before writing; `lastFile` is set before write-back so our own edit doesn't re-trigger.
- Taskbar matching needs TranslucentTB with `desktop_appearance.accent: opaque`;
  TranslucentTB colors are `#RRGGBBAA` (alpha LAST).
- `-SetWindowsAccent` is OFF by default: it can't reliably color the Win11 taskbar and
  toggling `ColorPrevalence` makes tiling WMs (komorebi) re-tile every window.
- Color is taken from `Monitor0` only; multi-monitor per-screen tinting is not implemented.

## Status
Working / in active use. README documents the full feature set. Known limitations:
single-monitor color source (`Monitor0`), no automated tests, WE may need a restart to
apply a written-back scheme color to its own theming. `docs/demo.gif` referenced in the
README is a placeholder (the `docs/` dir is not present).
