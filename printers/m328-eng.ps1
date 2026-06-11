add-printerport -name "\\gcuprint01\M328-ENG"

Add-Printer -Name "M328-ENG" -DriverName "HP Universal Printing PCL 6" -PortName "\\gcuprint01\M328-ENG"

$printer = Get-CimInstance -Class Win32_Printer -Filter "Name='M328-ENG'"
Invoke-CimMethod -InputObject $printer -MethodName SetDefaultPrinter

Pause
