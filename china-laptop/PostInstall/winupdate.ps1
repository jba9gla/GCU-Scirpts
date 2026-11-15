$ErrorActionPreference = 'Stop'
$rebootNeeded = $false
$failed = 0

try {
    Set-Service wuauserv -StartupType Manual -ErrorAction SilentlyContinue
    Start-Service wuauserv -ErrorAction SilentlyContinue
    $session = New-Object -ComObject Microsoft.Update.Session

    for ($pass = 1; $pass -le 3; $pass++) {
        Write-Output "Pass ${pass}: searching"
        $searcher = $session.CreateUpdateSearcher()
        $found = $searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Software'")
        if ($found.Updates.Count -eq 0) { Write-Output 'No more updates'; break }

        $coll = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($u in $found.Updates) {
            if (-not $u.EulaAccepted) { $u.AcceptEula() }
            [void]$coll.Add($u)
            Write-Output " - $($u.Title)"
        }

        $dl = $session.CreateUpdateDownloader()
        $dl.Updates = $coll
        [void]$dl.Download()

        $inst = $session.CreateUpdateInstaller()
        $inst.Updates = $coll
        $res = $inst.Install()
        Write-Output "Install result code: $($res.ResultCode)"
        if ($res.RebootRequired) { $rebootNeeded = $true }
        if ($res.ResultCode -notin 2, 3) { $failed++ }
    }
}
catch {
    Write-Output "Error: $($_.Exception.Message)"
    exit 2
}

if ($failed -gt 0)  { exit 1 }
if ($rebootNeeded)  { exit 3010 }
exit 0
