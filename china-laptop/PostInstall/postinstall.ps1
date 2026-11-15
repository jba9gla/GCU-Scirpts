Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$usbRoot   = Split-Path $PSScriptRoot -Parent
$log       = 'C:\Windows\Temp\postinstall.log'
$stateDir  = 'C:\ProgramData\GCUSetup'
$phaseFile = Join-Path $stateDir 'phase.txt'
$taskName  = 'GCU Setup - continue after restart'
$homeUrl   = 'https://www.gcu.ac.uk/'
$script:choice = ''

New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
$phase = '1'
if (Test-Path $phaseFile) { $phase = (Get-Content $phaseFile -Raw).Trim() }
if ($phase -eq 'done') { exit 0 }
$phase = [int]$phase

$cAccent  = [System.Drawing.Color]::FromArgb(24, 95, 165)
$cTrack   = [System.Drawing.Color]::FromArgb(245, 245, 242)
$cGreen   = [System.Drawing.Color]::FromArgb(39, 110, 30)
$cAmber   = [System.Drawing.Color]::FromArgb(133, 79, 11)
$cRed     = [System.Drawing.Color]::FromArgb(163, 45, 45)
$cGray    = [System.Drawing.Color]::FromArgb(136, 135, 128)
$cRunBack = [System.Drawing.Color]::FromArgb(230, 241, 251)
$cText    = [System.Drawing.Color]::FromArgb(30, 30, 30)
$cSub     = [System.Drawing.Color]::FromArgb(95, 94, 90)

function Write-Log([string]$m) {
    $line = "$(Get-Date -Format 'HH:mm:ss')  $m"
    Add-Content -Path $log -Value $line
    if ($script:txtLog) { $script:txtLog.AppendText($line + "`r`n") }
}

function Wait-UI($p) {
    while (-not $p.HasExited) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 100
    }
    $p.WaitForExit()
}

function Invoke-Tool([string]$exe, [string]$arguments) {
    $o = Join-Path $env:TEMP 'pi_out.txt'
    $e = Join-Path $env:TEMP 'pi_err.txt'
    $p = Start-Process -FilePath $exe -ArgumentList $arguments -PassThru -WindowStyle Hidden `
         -RedirectStandardOutput $o -RedirectStandardError $e
    $null = $p.Handle
    Wait-UI $p
    foreach ($f in $o, $e) {
        if (Test-Path $f) { Add-Content -Path $log -Value (Get-Content $f -Raw) }
    }
    return $p.ExitCode
}

function Test-Online {
    try {
        $r = Invoke-WebRequest -Uri 'http://www.msftconnecttest.com/connecttest.txt' -UseBasicParsing -TimeoutSec 5
        return ($r.StatusCode -eq 200)
    } catch { return $false }
}

function Confirm-Network([string]$context) {
    $script:lblStep.Text = 'Checking network connection...'
    [System.Windows.Forms.Application]::DoEvents()
    while (-not (Test-Online)) {
        Write-Log "No network ($context)"
        $msg = "Plug this laptop into Ethernet now.`r`n`r`n$context`r`n`r`nClick Retry once it's connected, or Cancel to continue without a network."
        $ans = [System.Windows.Forms.MessageBox]::Show(
            $form, $msg, 'GCU - Network connection needed',
            [System.Windows.Forms.MessageBoxButtons]::RetryCancel,
            [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($ans -eq [System.Windows.Forms.DialogResult]::Cancel) {
            Write-Log 'Continuing without network'
            return $false
        }
        Start-Sleep -Seconds 3
    }
    Write-Log 'Network OK'
    return $true
}

function Set-RegValues([string]$path, [hashtable]$values) {
    New-Item -Path $path -Force | Out-Null
    foreach ($k in $values.Keys) {
        $v = $values[$k]
        $type = if ($v -is [int]) { 'DWord' } else { 'String' }
        New-ItemProperty -Path $path -Name $k -Value $v -PropertyType $type -Force | Out-Null
    }
}

function Install-Drivers([string]$pass) {
    $root  = Join-Path $usbRoot 'PostInstall\Drivers'
    $model = (Get-CimInstance Win32_ComputerSystem).Model
    $d = Join-Path $root $model
    if (-not (Test-Path $d)) { $d = $root }
    if (-not (Test-Path $d)) { return @('fail', 'Drivers folder not found. Is the USB still in?') }
    Write-Log "Driver folder: $d ($pass)"

    # Hardware IDs of the devices in this laptop. USB network adapters (the USB-C
    # Ethernet dongle or a dock) are left out so their working driver is not replaced.
    $script:lblStep.Text = 'Reading hardware IDs...'
    [System.Windows.Forms.Application]::DoEvents()
    $ids = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($dev in Get-CimInstance Win32_PnPEntity) {
        if ($dev.PNPClass -eq 'Net' -and $dev.DeviceID -like 'USB\*') {
            Write-Log "Leaving alone: $($dev.Name)"
            continue
        }
        foreach ($id in @($dev.HardwareID) + @($dev.CompatibleID)) { if ($id) { [void]$ids.Add($id) } }
    }

    # Only drivers that match a device in this laptop, and not already installed in pass 1
    $doneFile = Join-Path $stateDir 'drivers-done.txt'
    $done = @(); if (Test-Path $doneFile) { $done = @(Get-Content $doneFile) }
    $infs = @(Get-ChildItem $d -Recurse -Filter '*.inf' -File)
    $idPattern = '\*[A-Za-z0-9]+|[A-Za-z0-9_]+\\[^\s,;"\]]+'
    $match = New-Object System.Collections.Generic.List[string]
    $n = 0
    foreach ($inf in $infs) {
        $n++
        if ($n % 20 -eq 0) {
            $script:lblStep.Text = "Checking driver files ($n of $($infs.Count))..."
            [System.Windows.Forms.Application]::DoEvents()
        }
        if ($done -contains $inf.FullName.Substring($d.Length)) { continue }
        $text = [IO.File]::ReadAllText($inf.FullName)
        foreach ($m in [regex]::Matches($text, $idPattern)) {
            if ($ids.Contains($m.Value)) { $match.Add($inf.FullName); break }
        }
    }
    Write-Log "$($infs.Count) driver files checked, $($match.Count) match this laptop"
    if ($match.Count -eq 0) { return @('ok', 'No new drivers needed') }

    $bad = 0; $i = 0
    foreach ($f in $match) {
        $i++
        $script:lblStep.Text = "Installing driver $i of $($match.Count)..."
        Write-Log "Driver: $($f.Substring($d.Length))"
        $rc = Invoke-Tool 'pnputil.exe' "/add-driver `"$f`" /install"
        if ($rc -notin 0, 259, 3010) { $bad++; Write-Log "  pnputil exit $rc" }
        Add-Content -Path $doneFile -Value $f.Substring($d.Length)
    }
    if ($bad -gt 0) { return @('warn', "$($match.Count - $bad) installed, $bad failed (see log)") }
    return @('ok', "$($match.Count) drivers installed")
}

# Silent switches for any .exe installers in PostInstall\Apps (MSI files need none).
$exeSwitches = @{
    # 'ExactInstallerName.exe' = '/silent'
}

# ---------- part 1: software and settings ----------
$steps1 = @(
 @{ Name = 'Set computer name from serial number'; Action = {
      $s = (Get-CimInstance Win32_BIOS).SerialNumber -replace '[^a-zA-Z0-9]', ''
      if ([string]::IsNullOrWhiteSpace($s) -or $s -match '^\d+$') { $s = 'WIN-' + (Get-Random -Maximum 99999999) }
      if ($s.Length -gt 15) { $s = $s.Substring(0, 15) }
      if ($env:COMPUTERNAME -eq $s) { return @('ok', "Already named $s") }
      Rename-Computer -NewName $s -Force -WarningAction SilentlyContinue -ErrorAction Stop
      return @('ok', "Will be $s after restart")
 }},
 @{ Name = 'Install Google Chrome'; Action = {
      $m = Get-ChildItem (Join-Path $usbRoot 'PostInstall\Chrome') -Filter '*.msi' -ErrorAction SilentlyContinue |
           Select-Object -First 1
      if (-not $m) { return @('fail', 'Chrome MSI not found in PostInstall\Chrome') }
      $rc = Invoke-Tool 'msiexec.exe' "/i `"$($m.FullName)`" /qn /norestart"
      if ($rc -in 0, 1641, 3010) { return @('ok', 'Installed') }
      return @('fail', "msiexec exit $rc")
 }},
 @{ Name = 'Set up Chrome and Edge'; Action = {
      # Chrome: no sign-in, sync, import, metrics, profile picker or ad-privacy prompts,
      # and no "make Chrome your default" prompt
      Set-RegValues 'HKLM:\SOFTWARE\Policies\Google\Chrome' @{
          BrowserSignin                       = 0
          SyncDisabled                        = 1
          PromotionalTabsEnabled              = 0
          DefaultBrowserSettingEnabled        = 0
          MetricsReportingEnabled             = 0
          ProfilePickerOnStartupAvailability  = 1
          PrivacySandboxPromptEnabled         = 0
          PrivacySandboxAdTopicsEnabled       = 0
          PrivacySandboxSiteEnabledAdsEnabled = 0
          PrivacySandboxAdMeasurementEnabled  = 0
          ImportAutofillFormData              = 0
          ImportBookmarks                     = 0
          ImportHistory                       = 0
          ImportHomepage                      = 0
          ImportSavedPasswords                = 0
          ImportSearchEngine                  = 0
      }
      # Edge: prompts not already covered by autounattend.xml
      Set-RegValues 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' @{
          DefaultBrowserSettingEnabled = 0
          AutoImportAtFirstRun         = 4
      }

      # Home page and start-up page. On a laptop that is not domain-joined or enrolled,
      # Chrome and Edge block the mandatory version of these policies, so they are set
      # as "recommended" and also in each browser's first-run preferences file.
      foreach ($base in 'HKLM:\SOFTWARE\Policies\Google\Chrome\Recommended',
                        'HKLM:\SOFTWARE\Policies\Microsoft\Edge\Recommended') {
          Set-RegValues $base @{
              HomepageLocation     = $homeUrl
              HomepageIsNewTabPage = 0
              ShowHomeButton       = 1
              RestoreOnStartup     = 4
          }
          Set-RegValues "$base\RestoreOnStartupURLs" @{ '1' = $homeUrl }
      }

      $prefs = @"
{
  "homepage": "$homeUrl",
  "homepage_is_newtabpage": false,
  "browser": { "show_home_button": true, "check_default_browser": false },
  "session": { "restore_on_startup": 4, "startup_urls": [ "$homeUrl" ] },
  "sync_promo": { "show_on_first_run_allowed": false },
  "distribution": {
    "skip_first_run_ui": true,
    "suppress_first_run_bubble": true,
    "suppress_first_run_default_browser_prompt": true,
    "import_bookmarks": false,
    "import_history": false,
    "import_home_page": false,
    "import_search_engine": false
  },
  "first_run_tabs": [ "$homeUrl" ]
}
"@
      $chromeDir = Join-Path $env:ProgramFiles 'Google\Chrome\Application'
      $edgeDir   = Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application'
      $notes = @()
      foreach ($dir in $chromeDir, $edgeDir) {
          if (Test-Path $dir) { Set-Content -Path (Join-Path $dir 'initial_preferences') -Value $prefs -Encoding ASCII }
          else { $notes += "Not found: $dir" }
      }

      # Chrome as default browser. Windows applies this file at each sign-in.
      if (-not (Test-Path (Join-Path $chromeDir 'chrome.exe'))) {
          return @('warn', 'Chrome not installed, so not set as default')
      }
      $assoc = Join-Path $stateDir 'DefaultAssociations.xml'
      @'
<?xml version="1.0" encoding="UTF-8"?>
<DefaultAssociations>
  <Association Identifier=".htm" ProgId="ChromeHTML" ApplicationName="Google Chrome" />
  <Association Identifier=".html" ProgId="ChromeHTML" ApplicationName="Google Chrome" />
  <Association Identifier="http" ProgId="ChromeHTML" ApplicationName="Google Chrome" />
  <Association Identifier="https" ProgId="ChromeHTML" ApplicationName="Google Chrome" />
</DefaultAssociations>
'@ | Set-Content -Path $assoc -Encoding ASCII
      Set-RegValues 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' @{ DefaultAssociationsConfiguration = $assoc }

      if ($notes) { return @('warn', ($notes -join '; ')) }
      return @('ok', 'Default, home page, no prompts')
 }},
 @{ Name = 'Install AppsAnywhere'; Action = {
      $dir = Join-Path $usbRoot 'PostInstall\Apps'
      if (-not (Test-Path $dir)) { return @('fail', 'PostInstall\Apps folder not found') }
      $files = Get-ChildItem $dir -File | Where-Object { $_.Extension -in '.msi', '.exe' } | Sort-Object Name
      if (-not $files) { return @('fail', 'No installers in PostInstall\Apps') }
      $bad = 0; $skipped = 0
      foreach ($f in $files) {
          Write-Log "Installing $($f.Name)"
          if ($f.Extension -eq '.msi') {
              $rc = Invoke-Tool 'msiexec.exe' "/i `"$($f.FullName)`" /qn /norestart"
          } elseif ($exeSwitches.ContainsKey($f.Name)) {
              $rc = Invoke-Tool $f.FullName $exeSwitches[$f.Name]
          } else {
              Write-Log "Skipped $($f.Name): no silent switch set"
              $skipped++
              continue
          }
          Write-Log "$($f.Name) exit code $rc"
          if ($rc -notin 0, 1641, 3010) { $bad++ }
      }
      if ($bad -gt 0)     { return @('fail', "$bad installer(s) failed") }
      if ($skipped -gt 0) { return @('warn', "$skipped skipped, no silent switch set") }
      return @('ok', "$($files.Count) installed")
 }},
 @{ Name = 'Create desktop shortcuts'; Action = {
      $desk = Join-Path $env:PUBLIC 'Desktop'
      $links = [ordered]@{
          'M365'    = 'https://www.office.com/'
          'Email'   = 'https://outlook.com/gcu.ac.uk'
          'zScaler' = 'https://portal-gcu-ac-uk.two.zscalerportal.net/#/home'
      }
      foreach ($n in $links.Keys) {
          Set-Content -Path (Join-Path $desk "$n.url") -Value "[InternetShortcut]`r`nURL=$($links[$n])" -Encoding ASCII
      }
      return @('ok', "$($links.Count) shortcuts created")
 }},
 @{ Name = 'Install Windows updates'; Action = {
      $w = Join-Path $usbRoot 'PostInstall\winupdate.ps1'
      if (-not (Test-Path $w)) { return @('fail', 'winupdate.ps1 not found') }
      if (-not (Confirm-Network 'Windows updates need an internet connection.')) {
          return @('warn', 'Skipped: no network')
      }
      $rc = Invoke-Tool 'powershell.exe' "-NoProfile -ExecutionPolicy Bypass -File `"$w`""
      switch ($rc) {
          0       { return @('ok',   'Up to date') }
          3010    { return @('ok',   'Installed, restart needed') }
          2       { return @('warn', 'No internet or update error, see log') }
          default { return @('warn', 'Some updates failed, see log') }
      }
 }},
 @{ Name = 'Prepare to continue after restart'; Action = {
      $drives = 'D E F G H I J K L M N O P Q R S T U V W X Y Z'
      $arg = "/c for %d in ($drives) do @if exist %d:\PostInstall\postinstall.bat call %d:\PostInstall\postinstall.bat"
      $a = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument $arg
      $t = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
      $t.Delay = 'PT20S'
      $p = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
      $s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
           -ExecutionTimeLimit (New-TimeSpan -Hours 4)
      Register-ScheduledTask -TaskName $taskName -Action $a -Trigger $t -Principal $p -Settings $s `
           -Force -ErrorAction Stop | Out-Null
      return @('ok', 'Drivers install after restart')
 }}
)

# ---------- part 2: drivers, first pass ----------
$steps2 = @(
 @{ Name = 'Install HP drivers (pass 1)'; Action = { Install-Drivers 'pass 1' } }
)

# ---------- part 3: drivers, second pass, then tidy up ----------
$steps3 = @(
 @{ Name = 'Install HP drivers (pass 2)'; Action = { Install-Drivers 'pass 2' } },
 @{ Name = 'Finish setup'; Action = {
      Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
      $wl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
      Set-ItemProperty -Path $wl -Name AutoAdminLogon -Value '0'
      Remove-ItemProperty -Path $wl -Name DefaultPassword, AutoLogonCount -ErrorAction SilentlyContinue
      return @('ok', 'Automatic sign-in turned off')
 }}
)

$steps = @($null, $steps1, $steps2, $steps3)[$phase]

# ---------- window ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = "GCU - Setting up this PC (part $phase of 3)"
$form.ClientSize = New-Object System.Drawing.Size(640, 516)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.ControlBox = $false
$form.TopMost = $true
$form.BackColor = [System.Drawing.Color]::White

function New-Label([string]$text, [int]$x, [int]$y, [int]$w, [int]$h, $font, $color) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.Size = New-Object System.Drawing.Size($w, $h)
    $l.Font = $font
    $l.ForeColor = $color
    $form.Controls.Add($l)
    return $l
}

function New-Bar([int]$x, [int]$y, [int]$w, [int]$h) {
    $t = New-Object System.Windows.Forms.Panel
    $t.Location = New-Object System.Drawing.Point($x, $y)
    $t.Size = New-Object System.Drawing.Size($w, $h)
    $t.BackColor = $cTrack
    $t.BorderStyle = 'FixedSingle'
    $f = New-Object System.Windows.Forms.Panel
    $f.BackColor = $cAccent
    $f.Location = New-Object System.Drawing.Point(0, 0)
    $f.Size = New-Object System.Drawing.Size(0, $t.ClientSize.Height)
    $t.Controls.Add($f)
    $form.Controls.Add($t)
    return @{ Track = $t; Fill = $f }
}

function Set-Bar($b, [double]$pct) {
    $b.Fill.Left = 0
    $b.Fill.Width = [int]($b.Track.ClientSize.Width * $pct / 100)
}

function Set-Row($it, [string]$status, [string]$note, $fore, $back) {
    $it.SubItems[1].Text = $status
    $it.SubItems[2].Text = $note
    foreach ($si in $it.SubItems) { $si.ForeColor = $fore; $si.BackColor = $back }
}

$fontUI    = New-Object System.Drawing.Font('Segoe UI', 10)
$fontSmall = New-Object System.Drawing.Font('Segoe UI', 9)
$fontHead  = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)

$headText = @('',
              'Part 1 of 3 - installing software and settings',
              'Part 2 of 3 - installing HP drivers',
              'Part 3 of 3 - installing HP drivers again')[$phase]
$script:title = New-Label $headText 20 14 600 30 $fontHead $cText

$lv = New-Object System.Windows.Forms.ListView
$lv.View = 'Details'
$lv.FullRowSelect = $true
$lv.HeaderStyle = 'Nonclickable'
$lv.BorderStyle = 'FixedSingle'
$lv.Scrollable = $true
$lv.BackColor = [System.Drawing.Color]::White
$lv.Font = $fontUI
$lv.Location = New-Object System.Drawing.Point(20, 56)
$lv.Size = New-Object System.Drawing.Size(600, 176)
[void]$lv.Columns.Add('Step', 260)
[void]$lv.Columns.Add('Status', 96)
[void]$lv.Columns.Add('Note', 220)
foreach ($s in $steps) {
    $it = New-Object System.Windows.Forms.ListViewItem($s.Name)
    $it.UseItemStyleForSubItems = $false
    [void]$it.SubItems.Add('')
    [void]$it.SubItems.Add('')
    Set-Row $it 'Waiting' '' $cGray ([System.Drawing.Color]::White)
    [void]$lv.Items.Add($it)
}
$form.Controls.Add($lv)

$script:lblStep = New-Label '' 20 244 600 22 $fontUI $cText
$script:stepBar = New-Bar 20 270 600 12
$null           = New-Label 'Progress for this part' 20 296 600 20 $fontSmall $cSub
$script:allBar  = New-Bar 20 318 600 20

$script:txtLog = New-Object System.Windows.Forms.TextBox
$script:txtLog.Multiline = $true
$script:txtLog.ReadOnly = $true
$script:txtLog.ScrollBars = 'Vertical'
$script:txtLog.BorderStyle = 'FixedSingle'
$script:txtLog.BackColor = $cTrack
$script:txtLog.ForeColor = $cSub
$script:txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)
$script:txtLog.Location = New-Object System.Drawing.Point(20, 352)
$script:txtLog.Size = New-Object System.Drawing.Size(600, 100)
$form.Controls.Add($script:txtLog)

$script:lblHint = New-Label 'Leave the USB stick in until part 3 finishes' 20 472 375 22 $fontSmall $cGray

function New-Button([string]$text, [int]$x) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object System.Drawing.Point($x, 466)
    $b.Size = New-Object System.Drawing.Size(105, 30)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderColor = $cGray
    $b.BackColor = [System.Drawing.Color]::White
    $b.ForeColor = $cText
    $b.Font = $fontSmall
    $b.Visible = $false
    $form.Controls.Add($b)
    return $b
}
$btnNow  = New-Button 'Restart now' 400
$btnStay = New-Button 'Cancel restart' 515
$btnNow.Add_Click({ $script:choice = 'now' })
$btnStay.Add_Click({ $script:choice = 'stay' })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 25
$timer.Add_Tick({
    $f = $script:stepBar.Fill
    $f.Left += 10
    if ($f.Left -ge $script:stepBar.Track.ClientSize.Width) { $f.Left = -$f.Width }
})

# ---------- run ----------
$form.Add_Shown({
    $form.Activate()
    $hard = 0; $warn = 0
    Write-Log "=== Part $phase of 3 started. USB root: $usbRoot"
    if ($phase -eq 1) { [void](Confirm-Network 'Windows updates need an internet connection.') }

    for ($i = 0; $i -lt $steps.Count; $i++) {
        $name = $steps[$i].Name
        $it = $lv.Items[$i]
        $it.EnsureVisible()
        Set-Row $it 'Running...' '' $cAccent $cRunBack
        $it.SubItems[0].ForeColor = $cText
        $script:lblStep.Text = "Step $($i + 1) of $($steps.Count): $name"
        $script:stepBar.Fill.Width = [int]($script:stepBar.Track.ClientSize.Width * 0.3)
        $script:stepBar.Fill.Left = -$script:stepBar.Fill.Width
        $timer.Start()
        Write-Log "--- $name ---"
        [System.Windows.Forms.Application]::DoEvents()

        try   { $r = & $steps[$i].Action }
        catch { $r = @('fail', $_.Exception.Message) }

        $timer.Stop()
        Set-Bar $script:stepBar 0
        $white = [System.Drawing.Color]::White
        switch ($r[0]) {
            'ok'   { Set-Row $it 'Done'     $r[1] $cGreen $white }
            'warn' { Set-Row $it 'Warnings' $r[1] $cAmber $white; $warn++ }
            default{ Set-Row $it 'FAILED'   $r[1] $cRed   $white; $hard++ }
        }
        Write-Log "Result: $($r[0]) - $($r[1])"
        Set-Bar $script:allBar (($i + 1) / $steps.Count * 100)
        [System.Windows.Forms.Application]::DoEvents()
    }

    Set-Bar $script:stepBar 100
    Write-Log "Part $phase finished. Failures: $hard  Warnings: $warn"

    # Move on to the next part even if a step failed, so the drivers still get installed.
    $next = if ($phase -lt 3) { [string]($phase + 1) } else { 'done' }
    Set-Content -Path $phaseFile -Value $next -Encoding ASCII

    $btnNow.Visible = $true
    $btnStay.Visible = $true
    if ($phase -eq 3) {
        $script:lblHint.Text = 'Setup complete. Remove the USB, then sign in as User1.'
        $script:lblHint.ForeColor = $cText
        $seconds = 30
    } else {
        $script:lblHint.Text = 'Leave the USB stick in. Setup carries on after the restart.'
        $seconds = 15
    }

    if ($hard -eq 0) {
        if ($phase -eq 3) { $script:title.Text = 'Setup complete' }
        for ($s = $seconds; $s -gt 0 -and $script:choice -eq ''; $s--) {
            $script:lblStep.Text = "Restarting in $s seconds..."
            for ($t = 0; $t -lt 10 -and $script:choice -eq ''; $t++) {
                [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100
            }
        }
        if ($script:choice -eq '') { $script:choice = 'now' }
    } else {
        $script:title.Text = "Part $phase finished with errors"
        $script:lblStep.Text = "$hard step(s) failed. See $log"
        $btnStay.Text = 'Close'
        while ($script:choice -eq '') { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }
    }

    if ($script:choice -eq 'now') { Restart-Computer -Force }
    $form.Close()
})

try   { [void]$form.ShowDialog() }
catch { Add-Content -Path $log -Value "GUI error: $($_.Exception.Message)" }
