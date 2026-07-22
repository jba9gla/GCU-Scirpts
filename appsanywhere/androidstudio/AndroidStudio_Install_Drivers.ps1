# Install Microsoft Visual C++ redistributables
Start-Process -FilePath "C:\Program Files\Android\Android Studio\bin\VC_redist.x86.exe" -ArgumentList "/install /quiet /norestart"
Start-Process -FilePath "C:\Program Files\Android\Android Studio\bin\VC_redist.x64.exe" -ArgumentList "/install /quiet /norestart"

# Install HAXM driver
Start-Process -FilePath "C:\ProgramData\Android\SDK\extras\Intel\Hardware_Accelerated_Execution_Manager\haxm-7.8.0-setup.exe" -ArgumentList "/S" -Wait;
Start-Process -FilePath "C:\Windows\System32\RUNDLL32.EXE" -ArgumentList "SETUPAPI.DLL,InstallHinfSection DefaultInstall 132 C:\ProgramData\Android\SDK\extras\google\Android_Emulator_Hypervisor_Driver\aehd.Inf" -Wait;

# Set file permissions
icacls "C:\ProgramData\Android\SDK" /t /grant *S-1-5-20:'(OI)(CI)F' /grant *S-1-5-11:'(OI)(CI)F';

[Environment]::Exit(0);
