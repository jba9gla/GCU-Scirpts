# ============================================================
# GCU - Cloudpaging Pre-Capture Script
# Disables background services and processes before capture
# Log: C:\CaptureLog\pre-capture.log
# ============================================================

$logPath = "C:\CaptureLog"
$logFile = "$logPath\pre-capture.log"

New-Item -ItemType Directory -Path $logPath -Force | Out-Null

function Write-Log {
    param([string]$Message)
    $entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    Add-Content -Path $logFile -Value $entry
    Write-Host $entry
}

Write-Log "=========================================="
Write-Log "GCU Cloudpaging Pre-Capture Script Started"
Write-Log "=========================================="

# ── Windows Update ──────────────────────────────────────────
$updateServices = @(
    "wuauserv",    # Windows Update
    "UsoSvc",      # Update Orchestrator
    "WaaSMedicSvc",# Windows Update Medic
    "BITS"         # Background Intelligent Transfer
)

foreach ($svc in $updateServices) {
    try {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s) {
            Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            Write-Log "STOPPED: $svc"
        }
    } catch {
        Write-Log "SKIPPED: $svc - $_"
    }
}

# ── Windows Store ────────────────────────────────────────────
$storeServices = @(
    "InstallService",  # Microsoft Store Install Service
    "StorSvc"          # Storage Service
)

foreach ($svc in $storeServices) {
    try {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s) {
            Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            Write-Log "STOPPED: $svc"
        }
    } catch {
        Write-Log "SKIPPED: $svc - $_"
    }
}

# Kill Store process
Get-Process -Name "WinStore.App" -ErrorAction SilentlyContinue | ForEach-Object {
    $_.Kill()
    Write-Log "KILLED PROCESS: WinStore.App"
}

# ── Microsoft 365 / Office ───────────────────────────────────
$officeServices = @(
    "ClickToRunSvc",   # Office Click-to-Run
    "OfficeSvcManager" # Office Service Manager
)

foreach ($svc in $officeServices) {
    try {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s) {
            Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            Write-Log "STOPPED: $svc"
        }
    } catch {
        Write-Log "SKIPPED: $svc - $_"
    }
}

$officeProcesses = @(
    "WINWORD", "EXCEL", "POWERPNT", "OUTLOOK", "ONENOTE",
    "TEAMS", "ms-teams", "OneDrive", "OfficeClickToRun",
    "AppVShNotify", "officec2rclient"
)

foreach ($proc in $officeProcesses) {
    Get-Process -Name $proc -ErrorAction SilentlyContinue | ForEach-Object {
        $_.Kill()
        Write-Log "KILLED PROCESS: $proc"
    }
}

# ── Browsers ─────────────────────────────────────────────────
$browserProcesses = @(
    "chrome", "msedge", "firefox", "brave", "opera"
)

foreach ($proc in $browserProcesses) {
    Get-Process -Name $proc -ErrorAction SilentlyContinue | ForEach-Object {
        $_.Kill()
        Write-Log "KILLED PROCESS: $proc"
    }
}

# Disable Edge update services
$edgeServices = @(
    "edgeupdate",
    "edgeupdatem",
    "MicrosoftEdgeElevationService"
)

foreach ($svc in $edgeServices) {
    try {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s) {
            Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            Write-Log "STOPPED: $svc"
        }
    } catch {
        Write-Log "SKIPPED: $svc - $_"
    }
}

# Disable Chrome update services
$chromeServices = @(
    "gupdate",
    "gupdatem"
)

foreach ($svc in $chromeServices) {
    try {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s) {
            Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            Write-Log "STOPPED: $svc"
        }
    } catch {
        Write-Log "SKIPPED: $svc - $_"
    }
}

# ── Telemetry and Diagnostics ────────────────────────────────
$telemetryServices = @(
    "DiagTrack",           # Connected User Experiences and Telemetry
    "dmwappushservice",    # WAP Push Message Routing
    "PcaSvc",              # Program Compatibility Assistant
    "WerSvc",              # Windows Error Reporting
    "wercplsupport"        # Problem Reports Control Panel
)

foreach ($svc in $telemetryServices) {
    try {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s) {
            Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            Write-Log "STOPPED: $svc"
        }
    } catch {
        Write-Log "SKIPPED: $svc - $_"
    }
}

# ── Search and Indexing ──────────────────────────────────────
$indexServices = @(
    "WSearch"  # Windows Search
)

foreach ($svc in $indexServices) {
    try {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s) {
            Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            Write-Log "STOPPED: $svc"
        }
    } catch {
        Write-Log "SKIPPED: $svc - $_"
    }
}

# ── Security / Antivirus ─────────────────────────────────────
$securityServices = @(
    "SecurityHealthService", # Windows Security Health
    "wscsvc"                 # Security Centre
)

foreach ($svc in $securityServices) {
    try {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s) {
            Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            Write-Log "STOPPED: $svc"
        }
    } catch {
        Write-Log "SKIPPED: $svc - $_"
    }
}

# ── Scheduled Tasks ──────────────────────────────────────────
$tasks = @(
    "\Microsoft\Windows\WindowsUpdate\Scheduled Start",
    "\Microsoft\Windows\WindowsUpdate\sih",
    "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
    "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
    "\Microsoft\Windows\Autochk\Proxy",
    "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
    "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
    "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
    "\Microsoft\Windows\PI\Sqm-Tasks",
    "\Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem",
    "\Microsoft\Windows\Shell\FamilySafetyMonitor",
    "\Microsoft\Windows\Shell\FamilySafetyRefresh"
)

foreach ($task in $tasks) {
    try {
        Disable-ScheduledTask -TaskPath (Split-Path $task) -TaskName (Split-Path $task -Leaf) -ErrorAction SilentlyContinue | Out-Null
        Write-Log "DISABLED TASK: $task"
    } catch {
        Write-Log "SKIPPED TASK: $task - $_"
    }
}

# ── Disable Network Location Awareness changes ───────────────
try {
    Stop-Service -Name "NlaSvc" -Force -ErrorAction SilentlyContinue
    Write-Log "STOPPED: NlaSvc (Network Location Awareness)"
} catch {
    Write-Log "SKIPPED: NlaSvc - $_"
}

# ── Final Summary ────────────────────────────────────────────
Write-Log "=========================================="
Write-Log "Pre-Capture Complete - Ready for Cloudpaging Studio"
Write-Log "Log saved to $logFile"
Write-Log "=========================================="

Write-Host ""
Write-Host "Pre-capture complete. You can now start your Cloudpaging Studio capture." -ForegroundColor Green
Write-Host "Log saved to $logFile" -ForegroundColor Cyan
