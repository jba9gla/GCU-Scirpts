# ============================================================
# GCU - Build ISO Script - Stream 3 (GitHub Generic Build)
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
#    - build-iso-stream3.ps1
#    - createhyper-v-stream3.ps1
#
# 4. Install Windows ADK (Deployment Tools only):
#    https://aka.ms/adk
#
# 5. Confirm Windows ISO is on G:
#    dir G:\
#
# 6. Run this script to build the ISO:
#    C:\HyperV\stream3\build-iso-stream3.ps1
#
# 7. Then run createhyper-v-stream3.ps1 to create the VM
# ============================================================

$sourceISO  = "G:\Win11_25H2_EnglishInternational_x64_v2.iso"
$workDir    = "C:\HyperV\WinISO"
$outputISO  = "C:\HyperV\stream3\Win11_stream3.iso"
$xmlSource  = "$PSScriptRoot\autounattend.xml"
$oscdimg    = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"

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

Write-Host "Done. ISO saved to $outputISO" -ForegroundColor Green
