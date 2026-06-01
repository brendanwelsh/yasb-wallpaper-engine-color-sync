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

  The chosen color is darkened (so white text stays legible) and written between
  the WP-SYNC markers in styles.css. Everything outside those markers is yours.

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

  # 0.0-1.0 multiplier applied to the color so white text stays readable.
  [double]$Darken = 0.55,

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
    if (($r + $g + $b) -lt 12) { return $null }   # skip near-black noise
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
    $r = 0; $gV = 0; $b = 0; $n = 0
    for ($yy = $y0; $yy -lt $y1; $yy++) {
      $row = $yy * $data.Stride
      for ($xx = $x0; $xx -lt $x1; $xx++) {
        $off = $row + ($xx * 4)
        $cb = $bytes[$off]; $cg = $bytes[$off+1]; $cr = $bytes[$off+2]   # BGRA
        $br = ($cr + $cg + $cb) / 3
        if ($br -lt 25 -or $br -gt 235) { continue }                    # drop near-black / near-white
        $r += $cr; $gV += $cg; $b += $cb; $n++
      }
    }
    if ($n -eq 0) { return $null }
    '#{0:X2}{1:X2}{2:X2}' -f [int]($r/$n), [int]($gV/$n), [int]($b/$n)
  } catch { $null }
}

function Apply-Darken([string]$hex) {
  if (-not $hex) { return $null }
  $r = [Convert]::ToInt32($hex.Substring(1,2),16)
  $g = [Convert]::ToInt32($hex.Substring(3,2),16)
  $b = [Convert]::ToInt32($hex.Substring(5,2),16)
  '#{0:X2}{1:X2}{2:X2}' -f [int][math]::Round($r*$Darken), [int][math]::Round($g*$Darken), [int][math]::Round($b*$Darken)
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

function Set-YasbColor([string]$hex) {
  if (-not (Test-Path $StylesPath)) { Log "styles.css not found: $StylesPath"; return $false }
  $bg     = ConvertTo-Rgba $hex $BackgroundAlpha
  $accent = $hex
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

  $source = ''
  $hex = Convert-SchemeToHex $wp.SavedScheme; if ($hex) { $source = 'saved-preset' }
  if (-not $hex) { $hex = Convert-SchemeToHex (Get-ProjectScheme $wp.File); if ($hex) { $source = 'project.json' } }
  if (-not $hex) {
    $preview = Find-PreviewImage $wp.File
    if ($preview) { $hex = Get-DominantHex $preview; if ($hex) { $source = 'preview-sample' } }
  }

  $name = Split-Path (Split-Path $wp.File -Parent) -Leaf
  if ($hex) {
    $hex = Apply-Darken $hex
    if ($hex -ne $script:lastHex) {
      if (Set-YasbColor $hex) { Log "$name  ->  $hex  ($source)"; $script:lastHex = $hex }
    }
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
