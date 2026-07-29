# ============================================================
# GCU - Build ISO and Create Hyper-V VM - Stream 3
# (GitHub Generic Build - Windows 11 24H2)
#
# PREREQUISITES:
# 1. Set execution policy:
#    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser -Force
#
# 2. Create folder structure:
#    New-Item -ItemType Directory -Path "C:\HyperV\stream3" -Force
#    New-Item -ItemType Directory -Path "C:\HyperV\WinISO" -Force
#
# 3. Save these files to C:\HyperV\stream3\:
#    - autounattend.xml (saved as UTF-8 without BOM in VS Code)
#    - deploy-stream3.ps1
#
# 4. Install Windows ADK (Deployment Tools only):
#    https://aka.ms/adk
#
# 5. Confirm Windows ISO path:
#    dir C:\HyperV\windows_iso\
#
# 6. Run this script:
#    C:\HyperV\stream3\deploy-stream3.ps1
#
# 7. Open Hyper-V Manager and connect to Win11-Stream3-GitHub
#    Once at the desktop take a clean checkpoint:
#    Checkpoint-VM -Name "Win11-Stream3-GitHub" -SnapshotName "Clean-PostInstall"
# ============================================================

# ── Enable Hyper-V if not already installed ──────────────────
$hyperv = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
if ($hyperv.State -ne "Enabled") {
    Write-Host "Hyper-V not detected - installing..." -ForegroundColor Yellow
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All -NoRestart
    Write-Host "Hyper-V installed - restart required before continuing." -ForegroundColor Red
    Write-Host "Please restart and run this script again." -ForegroundColor Red
    exit
} else {
    Write-Host "Hyper-V already enabled." -ForegroundColor Green
}

# ── Variables ────────────────────────────────────────────────
$sourceISO  = "C:\HyperV\windows_iso\SW_DVD9_Win_Pro_11_24H2.12_64BIT_English_Pro_Ent_EDU_N_MLF_X24-18358.iso"
$workDir    = "C:\HyperV\WinISO"
$outputISO  = "C:\HyperV\stream3\Win11_stream3.iso"
$xmlSource  = "$PSScriptRoot\autounattend.xml"
$oscdimg    = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
$vmName     = "Win11-Stream3-GitHub"
$vhdPath    = "C:\HyperV\VMs\$vmName\$vmName.vhdx"
$switchName = "Default Switch"

# ── Check ISO exists ─────────────────────────────────────────
if (-not (Test-Path $sourceISO)) {
    Write-Host "ERROR: Windows ISO not found at $sourceISO" -ForegroundColor Red
    Write-Host "Check the filename with: dir C:\HyperV\windows_iso\" -ForegroundColor Yellow
    exit
}

# ── Clean up previous build if exists ───────────────────────
Write-Host "Cleaning up previous build..." -ForegroundColor Cyan
Get-DiskImage -ImagePath $outputISO -ErrorAction SilentlyContinue | Dismount-DiskImage -ErrorAction SilentlyContinue
Remove-Item $outputISO -Force -ErrorAction SilentlyContinue
Remove-Item $workDir -Recurse -Force -ErrorAction SilentlyContinue

# ── Clean up existing VM if exists ──────────────────────────
if (Get-VM -Name $vmName -ErrorAction SilentlyContinue) {
    Write-Host "Removing existing VM..." -ForegroundColor Yellow
    Stop-VM -VMName $vmName -TurnOff -Force -ErrorAction SilentlyContinue
    Remove-VM -VMName $vmName -Force
    Remove-Item "C:\HyperV\VMs\$vmName" -Recurse -Force -ErrorAction SilentlyContinue
}

# ── Build ISO ────────────────────────────────────────────────
Write-Host "Mounting Windows ISO..." -ForegroundColor Cyan
$iso = Mount-DiskImage -ImagePath $sourceISO -PassThru
$driveLetter = ($iso | Get-Volume).DriveLetter

Write-Host "Copying ISO contents to $workDir..." -ForegroundColor Cyan
New-Item -ItemType Directory -Path $workDir -Force | Out-Null
Copy-Item -Path "$($driveLetter):\*" -Destination $workDir -Recurse -Force

Write-Host "Injecting autounattend.xml..." -ForegroundColor Cyan
Copy-Item $xmlSource "$workDir\autounattend.xml" -Force

Write-Host "Dismounting original ISO..." -ForegroundColor Cyan
Dismount-DiskImage -ImagePath $sourceISO

Write-Host "Rebuilding bootable ISO..." -ForegroundColor Cyan
& $oscdimg `
    -m -o -u2 -udfver102 `
    -bootdata:2`#p0,e,b"$workDir\boot\etfsboot.com"`#pEF,e,b"$workDir\efi\microsoft\boot\efisys.bin" `
    $workDir `
    $outputISO

Write-Host "ISO saved to $outputISO" -ForegroundColor Green

# ── Create VM ────────────────────────────────────────────────
Write-Host "Creating VM..." -ForegroundColor Cyan
New-Item -ItemType Directory -Path "C:\HyperV\VMs\$vmName" -Force | Out-Null

New-VM -Name $vmName `
       -Generation 2 `
       -MemoryStartupBytes 4GB `
       -SwitchName $switchName `
       -Path "C:\HyperV\VMs"

Write-Host "Creating and attaching disk..." -ForegroundColor Cyan
New-VHD -Path $vhdPath -SizeBytes 200GB -Dynamic
Add-VMHardDiskDrive -VMName $vmName -Path $vhdPath

Write-Host "Attaching ISO..." -ForegroundColor Cyan
Add-VMDvdDrive -VMName $vmName -Path $outputISO

Write-Host "Configuring CPUs and Secure Boot..." -ForegroundColor Cyan
Set-VM -VMName $vmName -ProcessorCount 2
Set-VMFirmware -VMName $vmName -EnableSecureBoot On

Write-Host "Configuring virtual TPM..." -ForegroundColor Cyan
$hgs = Get-HgsGuardian -Name UntrustedGuardian -ErrorAction SilentlyContinue
if (-not $hgs) {
    New-HgsGuardian -Name UntrustedGuardian -GenerateCertificates
}
$kp = New-HgsKeyProtector -Owner (Get-HgsGuardian UntrustedGuardian) -AllowUntrustedRoot
Set-VMKeyProtector -VMName $vmName -KeyProtector $kp.RawData
Enable-VMTPM -VMName $vmName

Write-Host "Setting boot order..." -ForegroundColor Cyan
$firmware = Get-VMFirmware -VMName $vmName
$bootOrder = $firmware.BootOrder
$dvdBoot  = $bootOrder | Where-Object { $_.Device -is [Microsoft.HyperV.PowerShell.DvdDrive] }
$diskBoot = $bootOrder | Where-Object { $_.Device -is [Microsoft.HyperV.PowerShell.HardDiskDrive] }
$netBoot  = $bootOrder | Where-Object { $_.BootType -eq "Network" }

$newBootOrder = @()
if ($dvdBoot)  { $newBootOrder += $dvdBoot }
if ($diskBoot) { $newBootOrder += $diskBoot }
if ($netBoot)  { $newBootOrder += $netBoot }

Set-VMFirmware -VMName $vmName -BootOrder $newBootOrder

Write-Host "Setting checkpoint type to Standard..." -ForegroundColor Cyan
Set-VM -VMName $vmName -CheckpointType Standard

Write-Host "Starting VM..." -ForegroundColor Cyan
Start-VM -VMName $vmName

Write-Host ""
Write-Host "Done. Connect to $vmName in Hyper-V Manager to watch the install." -ForegroundColor Green
Write-Host "Click through language and keyboard screens when prompted." -ForegroundColor Yellow
Write-Host "Once at the desktop, take a checkpoint:" -ForegroundColor Cyan
Write-Host "Checkpoint-VM -Name '$vmName' -SnapshotName 'Clean-PostInstall'" -ForegroundColor White
