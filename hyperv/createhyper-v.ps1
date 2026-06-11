$vmName     = "AppsAnywhere"
$winISO     = "C:\HyperV\Win11_unattended.iso"
$vhdPath    = "C:\HyperV\VMs\$vmName\$vmName.vhdx"
$switchName = "Default Switch"

Write-Host "Creating VM..." -ForegroundColor Cyan
New-VM -Name $vmName `
       -Generation 2 `
       -MemoryStartupBytes 4GB `
       -SwitchName $switchName `
       -Path "C:\HyperV\VMs"

Write-Host "Creating and attaching disk..." -ForegroundColor Cyan
New-VHD -Path $vhdPath -SizeBytes 200GB -Dynamic
Add-VMHardDiskDrive -VMName $vmName -Path $vhdPath

Write-Host "Attaching ISO..." -ForegroundColor Cyan
Add-VMDvdDrive -VMName $vmName -Path $winISO

Write-Host "Configuring CPUs and Secure Boot..." -ForegroundColor Cyan
Set-VM -VMName $vmName -ProcessorCount 2
Set-VMFirmware -VMName $vmName `
               -EnableSecureBoot On `
               -SecureBootTemplate MicrosoftWindows

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
$dvdBoot  = $firmware.BootOrder | Where-Object { $_.Device -is [Microsoft.HyperV.PowerShell.DvdDrive] }
$diskBoot = $firmware.BootOrder | Where-Object { $_.Device -is [Microsoft.HyperV.PowerShell.HardDiskDrive] }
$netBoot  = $firmware.BootOrder | Where-Object { $_.BootType -eq "Network" }
Set-VMFirmware -VMName $vmName -BootOrder $dvdBoot, $diskBoot, $netBoot

Write-Host "Starting VM..." -ForegroundColor Cyan
Start-VM -VMName $vmName

Write-Host "Done. Connect to $vmName in Hyper-V Manager to watch the install." -ForegroundColor Green
