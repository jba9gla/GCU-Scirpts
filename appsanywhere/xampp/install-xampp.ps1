# Start logging
Start-Transcript -Path "$env:SystemRoot\Temp\xampp-install.log" -Append

# Define installer path and install directory
$installer = "$PSScriptRoot\xampp-windows-x64-8.2.12-0-VS16-installer.exe"
$installDir = "C:\xampp"

# Run silent XAMPP installer
Start-Process $installer -ArgumentList "--mode unattended --unattendedmodeui none --installdir `"$installDir`"" -Wait

# Verify install and configure services
if (Test-Path "$installDir\xampp-control.exe") {
    & "$installDir\apache\bin\httpd.exe" -k install
    & "$installDir\mysql\bin\mysqld.exe" --install

    Start-Service -Name "Apache2.4" -ErrorAction SilentlyContinue
    Start-Service -Name "mysql" -ErrorAction SilentlyContinue

    Stop-Transcript
    Exit 0
} else {
    Stop-Transcript
    Exit 1
}
