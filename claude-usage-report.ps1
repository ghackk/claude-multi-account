param([switch]$Background, [switch]$Install)
$ErrorActionPreference = 'Stop'
$node = Get-Command node -ErrorAction SilentlyContinue
if (!$node) { if ($Install) { Write-Warning 'Usage history needs Node.js 22.13 or newer.' }; return }
$root = $PSScriptRoot
$report = Join-Path $root 'usage\report.js'
if ($Install) {
    & $node.Source --disable-warning=ExperimentalWarning (Join-Path $root 'usage\install.js')
    if ($LASTEXITCODE -ne 0) { return }
    $installed = Join-Path $HOME 'claude-accounts\claude-usage-report.ps1'
    $vbs = Join-Path $HOME 'claude-accounts\claude-usage-report-hidden.vbs'
    $directAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$installed`""
    $action = $directAction
    # Test/alternate homes must never run a live wscript probe.
    if (-not ($env:CLAUDE_USAGE_HOME -or $env:CLAUDE_USAGE_DIR) -and (Test-Path $vbs)) {
        $wshDisabled = @('HKLM:\SOFTWARE\Microsoft\Windows Script Host\Settings','HKCU:\SOFTWARE\Microsoft\Windows Script Host\Settings') |
            ForEach-Object { (Get-ItemProperty -Path $_ -Name Enabled -ErrorAction SilentlyContinue).Enabled } |
            Where-Object { $_ -eq 0 }
        if (-not $wshDisabled) {
            # wscript.exe is a GUI-subsystem host, never delegated to Windows Terminal, so it
            # launches fully hidden where powershell.exe -WindowStyle Hidden can still flash a
            # window. Probe it for real first: some locked-down machines disable Windows Script
            # Host entirely, in which case the task must keep working even if it flashes.
            $probe = Start-Process -FilePath 'wscript.exe' -ArgumentList "//B `"$vbs`"" -PassThru -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
            if ($probe -and $probe.ExitCode -eq 0) { $action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "//B `"$vbs`"" }
        }
    }
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 15)
    $settings = New-ScheduledTaskSettingsSet -Hidden -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 20)
    Register-ScheduledTask -TaskName 'Claude usage history' -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
    if (Test-Path (Join-Path $HOME 'claude-usage-history\reporting-disabled')) { Disable-ScheduledTask -TaskName 'Claude usage history' | Out-Null }
    & $installed -Background
    return
}
if ($Background) {
    Start-Process -FilePath $node.Source -WindowStyle Hidden -ArgumentList "--disable-warning=ExperimentalWarning `"$report`""
    return
}
& $node.Source --disable-warning=ExperimentalWarning $report
exit $LASTEXITCODE
