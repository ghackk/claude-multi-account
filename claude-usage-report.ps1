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
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$installed`""
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
