<#
.SYNOPSIS
  Install yasb-wallpaper-engine-color-sync to run hidden at login, and start it now.

.DESCRIPTION
  Creates a shortcut to start-hidden.vbs in your Startup folder so the watcher
  launches (with no console window) every time you log in. Then kicks it off for
  the current session so you don't have to log out to see it work.

  Re-running is safe: it overwrites the existing shortcut and restarts the watcher.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\install.ps1

.EXAMPLE
  # Register for login but don't start it right now:
  powershell -ExecutionPolicy Bypass -File .\install.ps1 -NoStart
#>
[CmdletBinding()]
param(
  # Don't start the watcher now, only register it for login.
  [switch]$NoStart
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$vbs  = Join-Path $here 'start-hidden.vbs'
$ps1  = Join-Path $here 'yasb-wallpaper-engine-color-sync.ps1'

if (-not (Test-Path $ps1)) { throw "Can't find yasb-wallpaper-engine-color-sync.ps1 next to install.ps1" }
if (-not (Test-Path $vbs)) { throw "Can't find start-hidden.vbs next to install.ps1" }

# Point start-hidden.vbs at the script's real location on this machine.
# VBScript string literals don't use backslash escaping, so write the path verbatim.
# Use a MatchEvaluator so '$' / '\' in the path aren't treated as regex substitutions.
$vbsText = Get-Content $vbs -Raw
$repl = [System.Text.RegularExpressions.MatchEvaluator] { param($m) 'SCRIPT = "' + $ps1 + '"' }
$vbsText = [regex]::Replace($vbsText, 'SCRIPT = ".*?"', $repl)
[System.IO.File]::WriteAllText($vbs, $vbsText, (New-Object System.Text.UTF8Encoding($false)))

# Drop a shortcut to the .vbs in the Startup folder.
$startup = [Environment]::GetFolderPath('Startup')
$lnk = Join-Path $startup 'yasb-wallpaper-engine-color-sync.lnk'
$sh = New-Object -ComObject WScript.Shell
$sc = $sh.CreateShortcut($lnk)
$sc.TargetPath = $vbs
$sc.WorkingDirectory = $here
$sc.Description = 'yasb-wallpaper-engine-color-sync (Wallpaper Engine -> YASB bar color)'
$sc.Save()
Write-Host "Registered for login: $lnk" -ForegroundColor Green

if (-not $NoStart) {
  # Stop any existing instance, then start fresh hidden.
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*yasb-wallpaper-engine-color-sync.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Start-Process wscript.exe -ArgumentList "`"$vbs`"" -WindowStyle Hidden
  Write-Host "Watcher started for this session." -ForegroundColor Green
}

Write-Host "Done. Switch wallpapers in Wallpaper Engine and your bar will follow." -ForegroundColor Cyan
