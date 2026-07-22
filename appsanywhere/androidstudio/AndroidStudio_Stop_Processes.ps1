Get-Process | ? { $_.Path -eq "C:\ProgramData\Android\SDK\platform-tools\adb.exe" } | Stop-Process;
Get-Process | ? { $_.Path -eq "C:\Program Files\Android\Android Studio\jbr\bin\java.exe" } | Stop-Process;

[Environment]::Exit(0);
