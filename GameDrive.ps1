<#
.SYNOPSIS
    Einfach: Wenn ein Volume mit dem angegebenen Label vorhanden ist, werden zwei feste Launcher gestartet.
.DESCRIPTION
    Polling-Loop mit Timeout: sobald das Volume gefunden wird, werden die fest konfigurierten Launcher
    (absolute Pfade auf C:\) gestartet.

TASK SCHEDULER HINWEISE
    Empfohlene Einstellungen für den Windows Task Scheduler (wenn GUI-Prozesse gestartet werden sollen):
      - Trigger: At startup / On workstation unlock / On an event (oder nach Bedarf)
      - Run only when user is logged on (ermöglicht interaktives Starten der GUI-Anwendungen)
      - Run with highest privileges
      - Configure for: Windows 10/11

    Schtasks-Beispiel (interaktiv, führt das Skript bei Systemstart aus, ersetzt <User> mit deinem Account):
      schtasks.exe /Create /TN "GameDriveLauncher" /TR "powershell.exe -ExecutionPolicy Bypass -File ""C:\\path\\to\\GameDrive.ps1""" /SC ONSTART /RL HIGHEST /IT /F /RU "<User>"

    Hinweis: /IT sorgt dafür, dass die Aufgabe interaktiv läuft (nur möglich, wenn ein Benutzer angegeben ist
    und "Run only when user is logged on" verwendet wird). Falls du den Task als Hintergrunddienst (nicht-interaktiv)
    laufen lassen willst, entferne /IT und nutze einen passenden RunLevel, beachte aber, dass GUI-Programme dann
    möglicherweise nicht sichtbar oder startbar sind.
#>

param(
    [string]$Label = "GameDrive",
    [int]$TimeoutSeconds = 600,
    [int]$PollIntervalSeconds = 10
)

# Feste, hartkodierte Launcher-Pfade (absolute Pfade auf C:\)
$Launcher1 = 'C:\\Games\\Launcher1.exe'
$Launcher2 = 'C:\\Games\\Launcher2.exe' 

function Find-DriveRootByLabel {
    param([string]$Label)

    try {
        $vol = Get-Volume -FileSystemLabel $Label -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($vol) {
            if ($vol.DriveLetter) { return "${($vol.DriveLetter)}:\\" }
            if ($vol.AccessPaths -and $vol.AccessPaths.Count -gt 0) { return $vol.AccessPaths[0] }
            if ($vol.Path) { return $vol.Path }
        }
    } catch {}

    try {
        $w = Get-CimInstance -ClassName Win32_Volume -Filter "Label='$Label'" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($w) {
            if ($w.DriveLetter) { return "$($w.DriveLetter):\\" }
            if ($w.Name) { return $w.Name }
        }
    } catch {}

    return $null
}

# Sicherstellen, dass die Launcher auf C:\ vorhanden sind
if (-not (Test-Path -Path $Launcher1 -PathType Leaf)) { exit 2 }
if (-not (Test-Path -Path $Launcher2 -PathType Leaf)) { exit 3 }

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)

while ((Get-Date) -lt $deadline) {
    $root = Find-DriveRootByLabel -Label $Label
    if ($root) {
        try {
            Start-Process -FilePath $Launcher1 -WindowStyle Normal -ErrorAction Stop
            Start-Process -FilePath $Launcher2 -WindowStyle Normal -ErrorAction Stop
            exit 0
        } catch {
            exit 4
        }
    }
    Start-Sleep -Seconds $PollIntervalSeconds
}

# Timeout: Laufwerk nicht gefunden
exit 1
