param(
    [string]$Label = "GameDrive",
    [switch]$KeepRunning,
    [int]$PollDelaySeconds = 2
)

# Feste, hartkodierte Launcher-Pfade (absolute Pfade auf C:\)
$Launcher1 = 'C:\Program Files (x86)\Steam\steam.exe'
$Launcher2 = 'C:\Program Files\Epic Games\Launcher\Engine\Binaries\Win64\EpicGamesLauncher.exe'

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

function Try-StartIfPresent {
    param([string]$Label)

    $root = Find-DriveRootByLabel -Label $Label
    if ($root) {
        try {
            Start-Process -FilePath $Launcher1 -WindowStyle Minimized -ErrorAction Stop
        } catch {
            Write-Error "Fehler beim Starten von $Launcher1 : $_"
            exit 4
        }
        try {
            Start-Process -FilePath $Launcher2 -WindowStyle Minimized -ErrorAction Stop
        } catch {
            Write-Error "Fehler beim Starten von $Launcher2 : $_"
            exit 4
        }
        return $true
    }
    return $false
}

# Sicherstellen, dass die Launcher auf C:\ vorhanden sind
if (-not (Test-Path -Path $Launcher1 -PathType Leaf)) { Write-Error "Launcher1 nicht gefunden: $Launcher1"; exit 2 }
if (-not (Test-Path -Path $Launcher2 -PathType Leaf)) { Write-Error "Launcher2 nicht gefunden: $Launcher2"; exit 3 }

# Sofort prüfen (für den Fall, dass die Platte schon eingesteckt ist)
if (Try-StartIfPresent -Label $Label) {
    if (-not $KeepRunning) { exit 0 }
    # wenn KeepRunning, weiterlaufen und weiterhin Events verarbeiten
}

$sourceId = "GameDrive_VolumeWatcher_$([guid]::NewGuid().ToString())"

try {
    # Registriere das WMI-Event (Win32_VolumeChangeEvent)
    Register-WmiEvent -Class Win32_VolumeChangeEvent -SourceIdentifier $sourceId | Out-Null
    Write-Host "Warte auf Volume-Ereignisse (SourceIdentifier: $sourceId). Label: $Label. KeepRunning: $KeepRunning"

    while ($true) {
        # Warte auf ein Event (blockierend). Kein Timeout gesetzt -> wartet beliebig lange
        $ev = Wait-Event -SourceIdentifier $sourceId
        if ($null -eq $ev) { continue }

        # EventType checken (je nach System: 2 oder 3 können relevante Typen sein)
        $evtType = $ev.SourceEventArgs.NewEvent.EventType 2>$null
        Write-Host "Event empfangen. EventType=$evtType"

        # Nur bei Device Arrival / relevante Events prüfen (häufig: 2 = Configuration Changed, 3 = Device Arrival)
        if ($evtType -in 2,3) {
            Start-Sleep -Seconds $PollDelaySeconds
            if (Try-StartIfPresent -Label $Label) {
                Write-Host "Launcher gestartet (Label gefunden: $Label)."
                if (-not $KeepRunning) {
                    # Aufräumen und beenden
                    Unregister-Event -SourceIdentifier $sourceId -ErrorAction SilentlyContinue
                    Remove-Event -SourceIdentifier $sourceId -ErrorAction SilentlyContinue
                    exit 0
                }
                # wenn KeepRunning, weiter lauschen (Launcher werden bei jedem Event neu gestartet)
            } else {
                Write-Host "Label '$Label' nicht gefunden nach Event."
            }
        }

        # Aufräumen des lokalen Event-Objekts
        try { Remove-Event -EventIdentifier $ev.EventIdentifier -ErrorAction SilentlyContinue } catch {}
    }
}
finally {
    # Stelle sicher, dass wir die Subscription entfernen, wenn das Skript endet
    try { Unregister-Event -SourceIdentifier $sourceId -ErrorAction SilentlyContinue } catch {}
    try { Remove-Event -SourceIdentifier $sourceId -ErrorAction SilentlyContinue } catch {}
}
