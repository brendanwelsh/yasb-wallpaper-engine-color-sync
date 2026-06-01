' Launch yasb-wallpaper-engine-color-sync with no console window (run at login).
' 1. Edit SCRIPT below to point at yasb-wallpaper-engine-color-sync.ps1 on your machine.
' 2. Put a shortcut to this .vbs in your Startup folder (Win+R -> shell:startup).
Dim sh, SCRIPT
Set sh = CreateObject("WScript.Shell")
SCRIPT = "C:\Users\YOU\path\to\yasb-wallpaper-engine-color-sync.ps1"
sh.Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & SCRIPT & """", 0, False
