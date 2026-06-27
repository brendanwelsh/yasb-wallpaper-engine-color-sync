<#
.SYNOPSIS
  Sync your YASB status-bar color to your active Wallpaper Engine wallpaper.

.DESCRIPTION
  Watches Wallpaper Engine's config.json (event-driven, no polling) and, whenever
  the active wallpaper changes, picks a representative color and writes it into a
  managed block in your YASB styles.css. YASB's `watch_stylesheet: true` then
  hot-reloads and your bar(s) re-tint instantly. Because every YASB bar shares one
  styles.css, a top bar and a bottom bar stay perfectly matched for free.

  Color is resolved in priority order:
    1. The schemecolor you saved for this wallpaper in Wallpaper Engine.
    2. The wallpaper author's default schemecolor (project.json).
    3. The dominant color sampled from the wallpaper's preview image (fallback).
  A scheme color of "0 0 0" is treated as unset (the common case where the author
  left it blank) and falls through to sampling.

  The chosen color is saturation-weighted and HSL-normalized for a clean, legible
  result, then written between the WP-SYNC markers in styles.css (bar background +
  a lighter active-workspace bubble). Everything outside those markers is yours.

  The same lighter accent is also pushed to komorebi's focused-window border
  (single/stack/monocle) via komorebic, live and without a retile, so the tiling
  border tracks the wallpaper too (-SetKomorebiBorder, on by default).

  When the color came from sampling, it is also written back into Wallpaper Engine's
  per-wallpaper scheme color (-WriteBackToWallpaperEngine, on by default), so WE's own
  theming matches and the blank "0 0 0" wallpapers get filled in. A one-time backup of
  WE's config.json is made and the edit is sanity-checked before writing.

.NOTES
  Repo: https://github.com/brendanwelsh/yasb-wallpaper-engine-color-sync
  License: MIT
#>
[CmdletBinding()]
param(
  # Wallpaper Engine config.json (Steam install path by default).
  [string]$WeConfig = "C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine\config.json",

  # Top-level user key inside WE config.json. Auto-detected when left empty.
  [string]$User = "",

  # Your YASB stylesheet. The script edits only the WP-SYNC managed block.
  [string]$StylesPath = "$env:USERPROFILE\.config\yasb\styles.css",

  # Optional: TranslucentTB (Store) settings.json. When present, the taskbar is re-tinted
  # to match the bar on each wallpaper change (TranslucentTB hot-reloads on file change).
  # The package family name is identical for every Store install.
  [string]$TranslucentTBSettings = "$env:LOCALAPPDATA\Packages\28017CharlesMilette.TranslucentTB_v826wp6bftszj\RoamingState\settings.json",

  # Target lightness (0-1) the bar color is normalized to, so white text stays readable.
  [double]$Lightness = 0.32,

  # Minimum saturation (0-1), applied ONLY to inputs with real chroma (see
  # ChromaThreshold). Vivid wallpapers get bolder bars; near-grays stay muted.
  [double]$Saturation = 0.6,

  # Only boost saturation when (max-min)/255 of the color exceeds this; near-grays
  # fall below it and are left dull (avoids tinting a gray wallpaper a hue).
  [double]$ChromaThreshold = 0.10,

  # A scheme color whose channels sum below this (out of 765) is treated as "unset"
  # and the preview is sampled instead. Wallpaper Engine stores "0 0 0" when the
  # author left the scheme color blank, which is usually what it means.
  [int]$BlackThreshold = 12,

  # Also write the chosen color back into Wallpaper Engine's scheme color for this
  # wallpaper (fills in the blank "0 0 0" ones so WE's own theming matches the bar).
  # On by default; pass -WriteBackToWallpaperEngine:$false to disable.
  [bool]$WriteBackToWallpaperEngine = $true,

  # Alpha (0-255) for the bar background (slight transparency looks nice).
  # Also set the Windows accent color (title bars; the taskbar only honors it on some
  # builds). OFF by default: toggling ColorPrevalence + broadcasting a color change makes
  # tiling WMs (komorebi) re-tile every window, which shifts your layout on each wallpaper
  # change. Enable only if your taskbar actually takes the accent and the retile is OK.
  [bool]$SetWindowsAccent = $false,

  # Also drive komorebi's focused-window border color from the accent, so the tiling
  # border tracks the wallpaper just like the bar and the active-workspace bubble.
  # Live via komorebic (no retile); silently no-ops if komorebi/komorebic isn't running.
  [bool]$SetKomorebiBorder = $true,

  # komorebic executable (on PATH for a standard komorebi install).
  [string]$KomorebicPath = "komorebic.exe",

  # Write the YASB styles.css managed block (the original target). On by default for
  # upstream users; pass -SetYasbColor:$false if you no longer run YASB.
  [bool]$SetYasbColor = $true,

  # Also drive PowerToys FancyZones' zone-highlight color (the fill shown while you drag a
  # window over a zone) from the accent, so the snap overlay tracks the wallpaper too.
  # Opt-in. FancyZones hot-reloads settings.json, so it shows on the next drag.
  [bool]$SetFancyZonesColor = $false,

  # PowerToys FancyZones settings.json (only used when -SetFancyZonesColor).
  [string]$FancyZonesSettings = "$env:LOCALAPPDATA\Microsoft\PowerToys\FancyZones\settings.json",

  [int]$BackgroundAlpha = 235,

  # Run once and exit instead of watching for changes.
  [switch]$Once,

  [string]$LogFile = "$env:USERPROFILE\.config\yasb\wp-color-sync.log"
)

Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class WinBroadcast {
    [DllImport("user32.dll", CharSet=CharSet.Auto)]
    static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, IntPtr wParam, string lParam, uint flags, uint timeout, out IntPtr result);
    public static void ColorSet() { IntPtr r; SendMessageTimeout((IntPtr)0xffff, 0x1A, IntPtr.Zero, "ImmersiveColorSet", 2, 300, out r); }
}
"@ -ErrorAction SilentlyContinue

function Log([string]$msg) {
  $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg"
  try { Add-Content -Path $LogFile -Value $line -Encoding utf8 } catch {}
  Write-Verbose $line
}

# --- Wallpaper Engine reading ------------------------------------------------

function Resolve-WeUser($json) {
  if ($User) { return $User }
  foreach ($p in $json.PSObject.Properties) {
    if ($p.Value.general -and $p.Value.general.wallpaperconfig) { return $p.Name }
  }
  return $null
}

function Get-ActiveWallpaper {
  try {
    $j = Get-Content $WeConfig -Raw -ErrorAction Stop | ConvertFrom-Json
    $u = Resolve-WeUser $j
    if (-not $u) { return $null }
    $w = $j.$u.general.wallpaperconfig
    $file = $w.selectedwallpapers.Monitor0.file
    if (-not $file) { return $null }
    $saved = $null
    $entry = $w.wproperties.PSObject.Properties | Where-Object { $_.Name -eq $file } | Select-Object -First 1
    if ($entry -and $entry.Value.Monitor0 -and $entry.Value.Monitor0.schemecolor) {
      $saved = $entry.Value.Monitor0.schemecolor
    }
    return [pscustomobject]@{ File = $file; SavedScheme = $saved }
  } catch { return $null }
}

function Get-ProjectScheme([string]$wallpaperFile) {
  $pj = Join-Path (Split-Path $wallpaperFile -Parent) 'project.json'
  if (-not (Test-Path $pj)) { return $null }
  try { (Get-Content $pj -Raw | ConvertFrom-Json).general.properties.schemecolor.value } catch { $null }
}

# Write the chosen color back into WE's per-wallpaper scheme color ("r g b" floats),
# so Wallpaper Engine's own theming matches the bar and the blank "0 0 0" gets filled.
# Safe: backs up config.json once, sanity-checks the re-serialized JSON before writing.
function Write-WeSchemeColor([string]$wallpaperFile, [string]$hex) {
  try {
    $r = [Convert]::ToInt32($hex.Substring(1,2),16) / 255.0
    $g = [Convert]::ToInt32($hex.Substring(3,2),16) / 255.0
    $b = [Convert]::ToInt32($hex.Substring(5,2),16) / 255.0
    $scheme = '{0:0.000000} {1:0.000000} {2:0.000000}' -f $r, $g, $b
    $orig = Get-Content $WeConfig -Raw -ErrorAction Stop
    $j = $orig | ConvertFrom-Json
    $u = Resolve-WeUser $j; if (-not $u) { return $false }
    $wpc = $j.$u.general.wallpaperconfig
    if (-not $wpc) { return $false }
    if (-not $wpc.wproperties) { Add-Member -InputObject $wpc -NotePropertyName 'wproperties' -NotePropertyValue ([pscustomobject]@{}) -Force }
    $entry = $wpc.wproperties.PSObject.Properties | Where-Object { $_.Name -eq $wallpaperFile } | Select-Object -First 1
    if (-not $entry) {
      Add-Member -InputObject $wpc.wproperties -NotePropertyName $wallpaperFile -NotePropertyValue ([pscustomobject]@{ Monitor0 = [pscustomobject]@{ schemecolor = $scheme } }) -Force
    } elseif (-not $entry.Value.Monitor0) {
      Add-Member -InputObject $entry.Value -NotePropertyName Monitor0 -NotePropertyValue ([pscustomobject]@{ schemecolor = $scheme }) -Force
    } elseif ($entry.Value.Monitor0.PSObject.Properties.Name -contains 'schemecolor') {
      $entry.Value.Monitor0.schemecolor = $scheme
    } else {
      Add-Member -InputObject $entry.Value.Monitor0 -NotePropertyName schemecolor -NotePropertyValue $scheme -Force
    }
    $new = $j | ConvertTo-Json -Depth 100 -Compress
    # safety: bail if serialization looks lossy, and make sure it re-parses
    if (-not $new -or $new.Length -lt ($orig.Length * 0.5)) { Log "WE write-back aborted (output too small)"; return $false }
    $null = $new | ConvertFrom-Json
    $bak = "$WeConfig.wpsync-backup.json"; if (-not (Test-Path $bak)) { Copy-Item $WeConfig $bak -ErrorAction SilentlyContinue }
    [System.IO.File]::WriteAllText($WeConfig, $new, (New-Object System.Text.UTF8Encoding($false)))
    return $true
  } catch { Log "WE write-back failed: $_"; return $false }
}

function Find-PreviewImage([string]$wallpaperFile) {
  $dir = Split-Path $wallpaperFile -Parent
  if (-not (Test-Path $dir)) { return $null }
  foreach ($n in 'preview.jpg','preview.png','preview.gif','preview.jpeg') {
    $p = Join-Path $dir $n; if (Test-Path $p) { return $p }
  }
  return $null
}

# --- Color helpers -----------------------------------------------------------

function Convert-SchemeToHex([string]$scheme) {
  if (-not $scheme) { return $null }
  $p = $scheme -split '\s+' | Where-Object { $_ -ne '' }
  if ($p.Count -lt 3) { return $null }
  try {
    $r = [int][math]::Round([double]$p[0] * 255)
    $g = [int][math]::Round([double]$p[1] * 255)
    $b = [int][math]::Round([double]$p[2] * 255)
    if (($r + $g + $b) -lt $BlackThreshold) { return $null }   # "0 0 0" = unset -> caller will sample
    '#{0:X2}{1:X2}{2:X2}' -f $r, $g, $b
  } catch { $null }
}

function Get-DominantHex([string]$imagePath) {
  if (-not (Test-Path $imagePath)) { return $null }
  try {
    $img = [System.Drawing.Image]::FromFile($imagePath)
    $w = 64; $h = 36
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.DrawImage($img, 0, 0, $w, $h); $g.Dispose(); $img.Dispose()
    $rect = New-Object System.Drawing.Rectangle 0, 0, $w, $h
    $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $bytes = New-Object byte[] ($data.Stride * $h)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
    $bmp.UnlockBits($data); $bmp.Dispose()
    $x0 = [int]($w * 0.10); $x1 = [int]($w * 0.90)
    $y0 = [int]($h * 0.15); $y1 = [int]($h * 0.85)
    $r = 0.0; $gV = 0.0; $b = 0.0; $tw = 0.0
    for ($yy = $y0; $yy -lt $y1; $yy++) {
      $row = $yy * $data.Stride
      for ($xx = $x0; $xx -lt $x1; $xx++) {
        $off = $row + ($xx * 4)
        $cb = $bytes[$off]; $cg = $bytes[$off+1]; $cr = $bytes[$off+2]   # BGRA
        $br = ($cr + $cg + $cb) / 3
        if ($br -lt 25 -or $br -gt 235) { continue }                    # drop near-black / near-white
        # Weight each pixel by its saturation^2 so vivid colors dominate and
        # washed-out sky / gray barely counts. This is what keeps the result
        # "on-hue" (e.g. Kermit green) instead of a muddy whole-image average.
        $mx = [math]::Max($cr, [math]::Max($cg, $cb)); $mn = [math]::Min($cr, [math]::Min($cg, $cb))
        $sat = if ($mx -eq 0) { 0 } else { ($mx - $mn) / $mx }
        $wt = $sat * $sat
        $r += $cr * $wt; $gV += $cg * $wt; $b += $cb * $wt; $tw += $wt
      }
    }
    if ($tw -le 0) { return $null }
    '#{0:X2}{1:X2}{2:X2}' -f [int]($r/$tw), [int]($gV/$tw), [int]($b/$tw)
  } catch { $null }
}

function Convert-HueToRgb([double]$p, [double]$q, [double]$t) {
  if ($t -lt 0) { $t += 1 }
  if ($t -gt 1) { $t -= 1 }
  if ($t -lt (1.0/6)) { return $p + ($q - $p) * 6 * $t }
  if ($t -lt 0.5)     { return $q }
  if ($t -lt (2.0/3)) { return $p + ($q - $p) * ((2.0/3) - $t) * 6 }
  return $p
}

# Preserve the sampled hue, but force a consistent, vivid, text-legible bar color:
# boost saturation to at least $Saturation and pin lightness to $Lightness.
function Convert-ToVibrant([string]$hex, [double]$targetL = -1) {
  if (-not $hex) { return $null }
  $r = [Convert]::ToInt32($hex.Substring(1,2),16) / 255.0
  $g = [Convert]::ToInt32($hex.Substring(3,2),16) / 255.0
  $b = [Convert]::ToInt32($hex.Substring(5,2),16) / 255.0
  $mx = [math]::Max($r,[math]::Max($g,$b)); $mn = [math]::Min($r,[math]::Min($g,$b))
  $l = ($mx + $mn) / 2; $d = $mx - $mn
  if ($d -eq 0) { $h = 0.0; $s = 0.0 }
  else {
    $s = if ($l -gt 0.5) { $d / (2 - $mx - $mn) } else { $d / ($mx + $mn) }
    if     ($mx -eq $r) { $h = ((($g - $b) / $d) % 6) }
    elseif ($mx -eq $g) { $h = ((($b - $r) / $d) + 2) }
    else                { $h = ((($r - $g) / $d) + 4) }
    $h = $h / 6.0; if ($h -lt 0) { $h += 1 }
  }
  # Boost saturation ONLY for colors that actually have a hue. A gray input has no
  # hue (h defaults to 0 = red), so forcing saturation would turn grays red — don't.
  if ($d -gt $ChromaThreshold) { $s = [math]::Max($s, $Saturation) }   # boost colored inputs; near-grays stay dull
  $l = if ($targetL -ge 0) { $targetL } else { $Lightness }        # default: dark bar bg
  if ($s -eq 0) { $r2 = $l; $g2 = $l; $b2 = $l }
  else {
    $q = if ($l -lt 0.5) { $l * (1 + $s) } else { $l + $s - $l * $s }
    $p = 2 * $l - $q
    $r2 = Convert-HueToRgb $p $q ($h + 1.0/3)
    $g2 = Convert-HueToRgb $p $q $h
    $b2 = Convert-HueToRgb $p $q ($h - 1.0/3)
  }
  '#{0:X2}{1:X2}{2:X2}' -f [int][math]::Round($r2*255), [int][math]::Round($g2*255), [int][math]::Round($b2*255)
}

function ConvertTo-Rgba([string]$hex, [int]$alpha) {
  $r = [Convert]::ToInt32($hex.Substring(1,2),16)
  $g = [Convert]::ToInt32($hex.Substring(3,2),16)
  $b = [Convert]::ToInt32($hex.Substring(5,2),16)
  $a = [math]::Round($alpha / 255.0, 3)
  "rgba($r, $g, $b, $a)"
}

# --- Apply to YASB styles.css ------------------------------------------------

$MARK_START = '/* WP-SYNC:START  -- managed by yasb-wallpaper-engine-color-sync; edit shape/text outside this block */'
$MARK_END   = '/* WP-SYNC:END */'

function Set-YasbColor([string]$barHex, [string]$accentHex) {
  if (-not (Test-Path $StylesPath)) { Log "styles.css not found: $StylesPath"; return $false }
  $bg     = ConvertTo-Rgba $barHex $BackgroundAlpha
  $accent = $accentHex
  $block  = @(
    $MARK_START
    ".yasb-bar { background-color: $bg; }"
    ".komorebi-workspaces .ws-btn.active { background-color: $accent; }"
    $MARK_END
  ) -join "`n"

  # Read as UTF-8 explicitly. Get-Content -Raw defaults to ANSI on PowerShell 5.1, which
  # garbles non-ASCII bytes and (read-garble-write each cycle) can balloon the file. Match
  # the UTF-8 we write so the round-trip is lossless.
  try { $css = [System.IO.File]::ReadAllText($StylesPath, [System.Text.UTF8Encoding]::new($false)) }
  catch { Log "could not read styles.css; skipping"; return $false }
  if ([string]::IsNullOrWhiteSpace($css)) { Log "styles.css empty/unreadable right now; skipping write to avoid clobbering it"; return $false }
  if ($css.Length -gt 1048576) { Log "styles.css unexpectedly large ($($css.Length) chars); skipping to avoid making it worse"; return $false }
  $pattern = [regex]::Escape($MARK_START) + '.*?' + [regex]::Escape($MARK_END)
  if ([regex]::IsMatch($css, $pattern, 'Singleline')) {
    # MatchEvaluator returns the block verbatim (no $-substitution pitfalls).
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator] { param($m) $block }
    $css = [regex]::Replace($css, $pattern, $evaluator, 'Singleline')
  } else {
    $css = $css.TrimEnd() + "`n`n" + $block + "`n"
  }
  # Write atomically (temp then replace) so YASB never reads a half-written/empty file,
  # and concurrent runs can't truncate it. BOM-free UTF8 (yasb reads styles.css as UTF-8).
  $tmp = "$StylesPath.tmp"
  [System.IO.File]::WriteAllText($tmp, $css, (New-Object System.Text.UTF8Encoding($false)))
  [System.IO.File]::Copy($tmp, $StylesPath, $true)
  Remove-Item $tmp -ErrorAction SilentlyContinue
  return $true
}

# --- Apply to the taskbar via TranslucentTB -----------------------------------

# TranslucentTB uses #RRGGBBAA (alpha LAST). Rewrites only the desktop_appearance color
# to a solid version of $hex; TranslucentTB watches the file and re-tints instantly.
function Set-TaskbarColor([string]$hex) {
  if (-not $hex -or -not (Test-Path $TranslucentTBSettings)) { return }
  try {
    $rgba = '#' + $hex.TrimStart('#') + 'FF'
    $json = [System.IO.File]::ReadAllText($TranslucentTBSettings, [System.Text.UTF8Encoding]::new($false))
    $pattern = '("desktop_appearance"\s*:\s*\{[^}]*?"color"\s*:\s*")#?[0-9A-Fa-f]{6,8}(")'
    if (-not [regex]::IsMatch($json, $pattern, 'Singleline')) { return }
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator] { param($m) $m.Groups[1].Value + $rgba + $m.Groups[2].Value }
    $json = [regex]::Replace($json, $pattern, $evaluator, 'Singleline')
    [System.IO.File]::WriteAllText($TranslucentTBSettings, $json, [System.Text.UTF8Encoding]::new($false))
  } catch { Log "set taskbar color failed: $_" }
}

# --- Apply to komorebi window borders -----------------------------------------

# Push the accent color to komorebi's focused-window border kinds (single/stack/monocle)
# via komorebic, so the tiling border matches the bar/wallpaper. Live and cheap (just a
# border repaint, no retile). The unfocused border is left as configured in komorebi.json.
# All output is swallowed and errors are caught, so this is a no-op when komorebi is down.
function Set-KomorebiBorder([string]$hex) {
  if (-not $hex) { return }
  try {
    $r = [Convert]::ToInt32($hex.Substring(1,2),16)
    $g = [Convert]::ToInt32($hex.Substring(3,2),16)
    $b = [Convert]::ToInt32($hex.Substring(5,2),16)
    foreach ($kind in 'single','stack','monocle') {
      & $KomorebicPath border-colour -w $kind $r $g $b *> $null
    }
    Log "set komorebi border -> $hex"
  } catch { Log "set komorebi border failed: $_" }
}

# --- Apply to the Windows accent color (taskbar + titlebars) ------------------

function Set-WindowsAccent([string]$hex) {
  if (-not $hex) { return }
  try {
    $r=[Convert]::ToInt32($hex.Substring(1,2),16); $g=[Convert]::ToInt32($hex.Substring(3,2),16); $b=[Convert]::ToInt32($hex.Substring(5,2),16)
    $abgr=([uint32]255*16777216)+([uint32]$b*65536)+([uint32]$g*256)+[uint32]$r
    $argb=([uint32]255*16777216)+([uint32]$r*65536)+([uint32]$g*256)+[uint32]$b
    $abgrI=[BitConverter]::ToInt32([BitConverter]::GetBytes($abgr),0)
    $argbI=[BitConverter]::ToInt32([BitConverter]::GetBytes($argb),0)
    $dwm='HKCU:\Software\Microsoft\Windows\DWM'
    $acc='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent'
    $per='HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    Set-ItemProperty $dwm -Name AccentColor -Value $abgrI -Type DWord
    Set-ItemProperty $dwm -Name ColorizationColor -Value $argbI -Type DWord
    Set-ItemProperty $dwm -Name ColorizationAfterglow -Value $argbI -Type DWord
    Set-ItemProperty $acc -Name AccentColorMenu -Value $abgrI -Type DWord
    # 8-shade palette (light -> dark) so taskbar/start pick a sensible tone
    $factors=@(1.75,1.5,1.25,1.0,0.8,0.65,0.5,0.4); $pb=New-Object System.Collections.Generic.List[byte]
    foreach($f in $factors){ $pb.Add([byte][Math]::Min(255,[int]($r*$f)));$pb.Add([byte][Math]::Min(255,[int]($g*$f)));$pb.Add([byte][Math]::Min(255,[int]($b*$f)));$pb.Add([byte]255) }
    Set-ItemProperty $acc -Name AccentPalette -Value ([byte[]]$pb.ToArray()) -Type Binary
    # Toggle ColorPrevalence off->on: this is what actually forces the Win11 taskbar to
    # repaint with the new accent (a plain broadcast alone usually doesn't take).
    Set-ItemProperty $per -Name ColorPrevalence -Value 0 -Type DWord
    try { [WinBroadcast]::ColorSet() } catch {}
    Start-Sleep -Milliseconds 400
    Set-ItemProperty $per -Name ColorPrevalence -Value 1 -Type DWord
    try { [WinBroadcast]::ColorSet() } catch {}
    Log "set Windows accent -> $hex"
  } catch { Log "set Windows accent failed: $_" }
}

# --- Apply to PowerToys FancyZones --------------------------------------------

# Push the accent into FancyZones' zone-highlight color (the fill shown while a window is
# dragged over a zone). Only that one settings key is rewritten; everything else in
# settings.json is preserved. PowerToys watches the file and hot-reloads, so the new color
# appears on the next drag (worst case, after the next PowerToys restart). No-ops cleanly
# if PowerToys isn't installed or the key isn't present.
function Set-FancyZonesColor([string]$hex) {
  if (-not $hex -or -not (Test-Path $FancyZonesSettings)) { return }
  try {
    $json = [System.IO.File]::ReadAllText($FancyZonesSettings, [System.Text.UTF8Encoding]::new($false))
    $pattern = '("fancyzones_zoneHighlightColor"\s*:\s*\{\s*"value"\s*:\s*")#?[0-9A-Fa-f]{6,8}(")'
    if (-not [regex]::IsMatch($json, $pattern)) { Log "FancyZones highlight key not found; skipping"; return }
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator] { param($m) $m.Groups[1].Value + $hex + $m.Groups[2].Value }
    $json = [regex]::Replace($json, $pattern, $evaluator)
    [System.IO.File]::WriteAllText($FancyZonesSettings, $json, (New-Object System.Text.UTF8Encoding($false)))
    Log "set FancyZones highlight -> $hex"
  } catch { Log "set FancyZones color failed: $_" }
}

# --- Main --------------------------------------------------------------------

$script:lastFile = ''
$script:lastHex  = ''

function Update-Color {
  $wp = Get-ActiveWallpaper
  if (-not $wp) { return }
  if ($wp.File -eq $script:lastFile) { return }

  $source = ''; $sampled = $false
  $hex = Convert-SchemeToHex $wp.SavedScheme; if ($hex) { $source = 'saved-scheme' }
  if (-not $hex) { $hex = Convert-SchemeToHex (Get-ProjectScheme $wp.File); if ($hex) { $source = 'project-scheme' } }
  if (-not $hex) {
    $preview = Find-PreviewImage $wp.File
    if ($preview) { $hex = Get-DominantHex $preview; if ($hex) { $source = 'preview-sample'; $sampled = $true } }
  }

  $name = Split-Path (Split-Path $wp.File -Parent) -Leaf
  if ($hex) {
    $barHex    = Convert-ToVibrant $hex
    $accentHex = Convert-ToVibrant $hex ([math]::Min(0.62, $Lightness + 0.24))  # lighter bubble that pops on the bar
    $script:lastFile = $wp.File   # set before write-back so our own config write doesn't re-trigger
    if ($barHex -ne $script:lastHex) {
      if ($SetYasbColor)       { Set-YasbColor $barHex $accentHex | Out-Null }
      Set-TaskbarColor $barHex
      if ($SetKomorebiBorder)  { Set-KomorebiBorder $accentHex }   # tiling border matches the active-workspace bubble
      if ($SetFancyZonesColor) { Set-FancyZonesColor $accentHex }  # FancyZones snap overlay matches the wallpaper
      if ($SetWindowsAccent)   { Set-WindowsAccent $accentHex }    # brighter shade so the dark-mode taskbar reads as a clearer color
      Log "$name  ->  bar $barHex / accent $accentHex  ($source)"
      $script:lastHex = $barHex
    }
    # Fill in WE's blank ("0 0 0") scheme color with what we sampled, so WE matches the bar.
    if ($sampled -and $WriteBackToWallpaperEngine) {
      if (Write-WeSchemeColor $wp.File $barHex) { Log "  -> wrote scheme color $barHex back to Wallpaper Engine" }
    }
    return
  } else {
    Log "$name  ->  NO COLOR FOUND (left styles.css unchanged)"
  }
  $script:lastFile = $wp.File
}

Log "yasb-wallpaper-engine-color-sync started (styles: $StylesPath)"
Update-Color
if ($Once) { Log 'ran once (-Once); exiting'; return }

$dir  = Split-Path $WeConfig -Parent
$file = Split-Path $WeConfig -Leaf
$fsw  = New-Object System.IO.FileSystemWatcher $dir, $file
$fsw.NotifyFilter = [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::Size

while ($true) {
  $changed = $fsw.WaitForChanged([System.IO.WatcherChangeTypes]::Changed, 3600000)
  if ($changed.TimedOut) { continue }
  Start-Sleep -Milliseconds 250   # let WE finish writing
  Update-Color
}
