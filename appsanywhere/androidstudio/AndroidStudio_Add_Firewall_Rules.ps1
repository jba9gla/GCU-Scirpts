#Add Firewall Rules
New-NetFirewallRule -DisplayName "Android Studio 2026.1" -Direction Inbound -Program "C:\Program Files\Android\Android Studio\jbr\bin\java.exe" -Description "Android Studio 2026.1" -Profile Any -Action Allow -Enabled True;
New-NetFirewallRule -DisplayName "Android Studio 2026.1" -Direction Inbound -Program "C:\Program Files\Android\Android Studio\bin\studio64.exe" -Description "Android Studio 2026.1" -Profile Any -Action Allow -Enabled True;
New-NetFirewallRule -DisplayName "Android Studio 2026.1" -Direction Inbound -Program "C:\ProgramData\Android\sdk\platform-tools\adb.exe" -Description "Android Studio 2026.1" -Profile Any -Action Allow -Enabled True;

[Environment]::Exit(0);
