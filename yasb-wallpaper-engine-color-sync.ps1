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

  When the color came from sampling, it is also written back into Wallpaper Engine's
  per-wallpaper scheme color (-WriteBackToWallpaperEngine, on by default), so WE's own
  theming matches and the blank "0 0 0" wallpapers get filled in. A one-time backup of
  WE's config.json is made and the edit is sanity-checked before writing.

.NOTES
  Repo: https://github.com/<you>/yasb-wallpaper-engine-color-sync
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

  # Target lightness (0-1) the bar color is normalized to, so white text stays readable.
  [double]$Lightness = 0.32,

  # Minimum saturation (0-1); muddy/desaturated samples are boosted so the hue reads clearly.
  # (Only used for the optional -SampleWhenNoScheme path.)
  [double]$Saturation = 0.55,

  # A scheme color whose channels sum below this (out of 765) is treated as "unset"
  # and the preview is sampled instead. Wallpaper Engine stores "0 0 0" when the
  # author left the scheme color blank, which is usually what it means.
  [int]$BlackThreshold = 12,

  # Also write the chosen color back into Wallpaper Engine's scheme color for this
  # wallpaper (fills in the blank "0 0 0" ones so WE's own theming matches the bar).
  # On by default; pass -WriteBackToWallpaperEngine:$false to disable.
  [bool]$WriteBackToWallpaperEngine = $true,

  # Alpha (0-255) for the bar background (slight transparency looks nice).
  [int]$BackgroundAlpha = 235,

  # Run once and exit instead of watching for changes.
  [switch]$Once,

  [string]$LogFile = "$env:USERPROFILE\.config\yasb\wp-color-sync.log"
)

Add-Type -AssemblyName System.Drawing

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
  $s = [math]::Max($s, $Saturation)                                # boost washed-out colors
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

  $css = Get-Content $StylesPath -Raw
  $pattern = [regex]::Escape($MARK_START) + '.*?' + [regex]::Escape($MARK_END)
  if ([regex]::IsMatch($css, $pattern, 'Singleline')) {
    # MatchEvaluator returns the block verbatim (no $-substitution pitfalls).
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator] { param($m) $block }
    $css = [regex]::Replace($css, $pattern, $evaluator, 'Singleline')
  } else {
    $css = $css.TrimEnd() + "`n`n" + $block + "`n"
  }
  # BOM-free UTF8 (yasb reads styles.css as UTF-8)
  [System.IO.File]::WriteAllText($StylesPath, $css, (New-Object System.Text.UTF8Encoding($false)))
  return $true
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
      if (Set-YasbColor $barHex $accentHex) { Log "$name  ->  bar $barHex / active $accentHex  ($source)"; $script:lastHex = $barHex }
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
