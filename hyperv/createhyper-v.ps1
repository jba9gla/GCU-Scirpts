# ============================================================
# GCU - Create Hyper-V VM Script
# Creates a Windows 11 Pro VM with unattended install
# ============================================================

# ── Enable Hyper-V if not already installed ──────────────────
$hyperv = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
if ($hyperv.State -ne "Enabled") {
    Write-Host "Hyper-V not detected - installing..." -ForegroundColor Yellow
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All -NoRestart
    Write-Host "Hyper-V installed - a restart is required before continuing." -ForegroundColor Red
    Write-Host "Please restart and run this script again." -ForegroundColor Red
    exit
} else {
    Write-Host "Hyper-V already enabled." -ForegroundColor Green
}

# ── Variables ────────────────────────────────────────────────
$vmName     = "AppsAnywhere"
$winISO     = "C:\HyperV\Win11_unattended.iso"
$vhdPath    = "C:\HyperV\VMs\$vmName\$vmName.vhdx"
$switchName = "Default Switch"

# ── Create folder structure if needed ───────────────────────
New-Item -ItemType Directory -Path "C:\HyperV\VMs\$vmName" -Force | Out-Null

# ── Create VM ────────────────────────────────────────────────
Write-Host "Creating VM..." -ForegroundColor Cyan
New-VM -Name $vmName `
       -Generation 2 `
       -MemoryStartupBytes 4GB `
       -SwitchName $switchName `
       -Path "C:\HyperV\VMs"

# ── Create and attach disk ───────────────────────────────────
Write-Host "Creating and attaching disk..." -ForegroundColor Cyan
New-VHD -Path $vhdPath -SizeBytes 200GB -Dynamic
Add-VMHardDiskDrive -VMName $vmName -Path $vhdPath

# ── Attach ISO ───────────────────────────────────────────────
Write-Host "Attaching ISO..." -ForegroundColor Cyan
Add-VMDvdDrive -VMName $vmName -Path $winISO

# ── Configure CPUs and Secure Boot ──────────────────────────
Write-Host "Configuring CPUs and Secure Boot..." -ForegroundColor Cyan
Set-VM -VMName $vmName -ProcessorCount 2
Set-VMFirmware -VMName $vmName `
               -EnableSecureBoot On `
               -SecureBootTemplate MicrosoftWindows

# ── Configure virtual TPM ────────────────────────────────────
Write-Host "Configuring virtual TPM..." -ForegroundColor Cyan
$hgs = Get-HgsGuardian -Name UntrustedGuardian -ErrorAction SilentlyContinue
if (-not $hgs) {
    New-HgsGuardian -Name UntrustedGuardian -GenerateCertificates
}
$kp = New-HgsKeyProtector -Owner (Get-HgsGuardian UntrustedGuardian) -AllowUntrustedRoot
Set-VMKeyProtector -VMName $vmName -KeyProtector $kp.RawData
Enable-VMTPM -VMName $vmName

# ── Set boot order ───────────────────────────────────────────
Write-Host "Setting boot order..." -ForegroundColor Cyan
$firmware = Get-VMFirmware -VMName $vmName
$dvdBoot  = $firmware.BootOrder | Where-Object { $_.Device -is [Microsoft.HyperV.PowerShell.DvdDrive] }
$diskBoot = $firmware.BootOrder | Where-Object { $_.Device -is [Microsoft.HyperV.PowerShell.HardDiskDrive] }
$netBoot  = $firmware.BootOrder | Where-Object { $_.BootType -eq "Network" }
Set-VMFirmware -VMName $vmName -BootOrder $dvdBoot, $diskBoot, $netBoot

# ── Set checkpoint type to Standard ─────────────────────────
Write-Host "Setting checkpoint type to Standard..." -ForegroundColor Cyan
Set-VM -VMName $vmName -CheckpointType Standard

# ── Start VM ─────────────────────────────────────────────────
Write-Host "Starting VM..." -ForegroundColor Cyan
Start-VM -VMName $vmName

Write-Host ""
Write-Host "Done. Connect to $vmName in Hyper-V Manager to watch the install." -ForegroundColor Green
Write-Host "Once at the desktop, take a checkpoint:" -ForegroundColor Cyan
Write-Host "Checkpoint-VM -Name '$vmName' -SnapshotName 'Clean-PostInstall'" -ForegroundColor White
