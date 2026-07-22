# ============================================================
# GCU - Cloudpaging Pre-Capture Script
# Disables background services and processes before capture
# Log: C:\CaptureLog\pre-capture.log
# ============================================================

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser -Force

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
    "wuauserv",
    "UsoSvc",
    "WaaSMedicSvc",
    "BITS"
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
    "InstallService",
    "StorSvc",
    "WSService"        # Windows Store Service
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

$storeProcesses = @(
    "WinStore.App",
    "Microsoft.WindowsStore"
)

foreach ($proc in $storeProcesses) {
    Get-Process -Name $proc -ErrorAction SilentlyContinue | ForEach-Object {
        $_.Kill()
        Write-Log "KILLED PROCESS: $proc"
    }
}

# ── OneDrive ─────────────────────────────────────────────────
$oneDriveServices = @(
    "OneSyncSvc",      # OneDrive Sync Service
    "FileSyncHelper"   # OneDrive File Co-authoring
)

foreach ($svc in $oneDriveServices) {
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

$oneDriveProcesses = @(
    "OneDrive",
    "OneDriveStandaloneUpdater",
    "FileCoAuth"       # OneDrive File Co-authoring executable
)

foreach ($proc in $oneDriveProcesses) {
    Get-Process -Name $proc -ErrorAction SilentlyContinue | ForEach-Object {
        $_.Kill()
        Write-Log "KILLED PROCESS: $proc"
    }
}

# ── Microsoft 365 / Office ───────────────────────────────────
$officeServices = @(
    "ClickToRunSvc",
    "OfficeSvcManager"
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
    "TEAMS", "ms-teams", "OfficeClickToRun",
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

# ── Microsoft Edge Update ────────────────────────────────────
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

$edgeProcesses = @(
    "MicrosoftEdgeUpdate",
    "MicrosoftEdge"
)

foreach ($proc in $edgeProcesses) {
    Get-Process -Name $proc -ErrorAction SilentlyContinue | ForEach-Object {
        $_.Kill()
        Write-Log "KILLED PROCESS: $proc"
    }
}

# ── Chrome Update ────────────────────────────────────────────
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

# ── Windows Widgets ──────────────────────────────────────────
$widgetProcesses = @(
    "Widgets",
    "WidgetService"
)

foreach ($proc in $widgetProcesses) {
    Get-Process -Name $proc -ErrorAction SilentlyContinue | ForEach-Object {
        $_.Kill()
        Write-Log "KILLED PROCESS: $proc"
    }
}

try {
    $s = Get-Service -Name "WpnService" -ErrorAction SilentlyContinue
    if ($s) {
        Set-Service -Name "WpnService" -StartupType Disabled -ErrorAction SilentlyContinue
        Stop-Service -Name "WpnService" -Force -ErrorAction SilentlyContinue
        Write-Log "STOPPED: WpnService (Windows Push Notifications - used by Widgets)"
    }
} catch {
    Write-Log "SKIPPED: WpnService - $_"
}

# ── Telemetry and Diagnostics ────────────────────────────────
$telemetryServices = @(
    "DiagTrack",
    "dmwappushservice",
    "PcaSvc",
    "WerSvc",
    "wercplsupport"
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
try {
    Set-Service -Name "WSearch" -StartupType Disabled -ErrorAction SilentlyContinue
    Stop-Service -Name "WSearch" -Force -ErrorAction SilentlyContinue
    Write-Log "STOPPED: WSearch"
} catch {
    Write-Log "SKIPPED: WSearch - $_"
}

# ── Security ─────────────────────────────────────────────────
$securityServices = @(
    "SecurityHealthService",
    "wscsvc"
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
    "\Microsoft\Windows\Shell\FamilySafetyRefresh",
    "\Microsoft\Windows\Widgets\UserSessionMessageBroker"
)

foreach ($task in $tasks) {
    try {
        Disable-ScheduledTask -TaskPath (Split-Path $task) -TaskName (Split-Path $task -Leaf) -ErrorAction SilentlyContinue | Out-Null
        Write-Log "DISABLED TASK: $task"
    } catch {
        Write-Log "SKIPPED TASK: $task - $_"
    }
}

# ── Network Location Awareness ───────────────────────────────
try {
    Stop-Service -Name "NlaSvc" -Force -ErrorAction SilentlyContinue
    Write-Log "STOPPED: NlaSvc"
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
