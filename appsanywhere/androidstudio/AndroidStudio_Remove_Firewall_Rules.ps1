#Remove Firewall Rules
Get-NetFirewallRule | Where-Object { $_.DisplayName -eq "Android Studio 2026.1" } | Remove-NetFirewallRule

[Environment]::Exit(0);
