param([switch]$Background, [switch]$Install, [switch]$Disable, [switch]$Enable, [switch]$Dashboard)
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
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 30)
    $settings = New-ScheduledTaskSettingsSet -Hidden -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 20)
    Register-ScheduledTask -TaskName 'Claude usage history' -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
    if (Test-Path (Join-Path $HOME 'claude-usage-history\reporting-disabled')) { Disable-ScheduledTask -TaskName 'Claude usage history' | Out-Null }
    & $installed -Background
    return
}
if ($Disable) { & $node.Source --disable-warning=ExperimentalWarning $report disable; Disable-ScheduledTask -TaskName 'Claude usage history' -ErrorAction SilentlyContinue | Out-Null; return }
if ($Enable) { & $node.Source --disable-warning=ExperimentalWarning $report enable; Enable-ScheduledTask -TaskName 'Claude usage history' -ErrorAction SilentlyContinue | Out-Null; & $PSCommandPath -Background; return }
if ($Dashboard) {
    Start-Process -FilePath $node.Source -WindowStyle Hidden -ArgumentList "--disable-warning=ExperimentalWarning `"$report`" serve"
    Start-Process 'http://127.0.0.1:3142'
    return
}
if ($Background) {
    if ($env:MULTI_CLAUDE_NO_REPORT -eq '1') { return }
    Start-Process -FilePath $node.Source -WindowStyle Hidden -ArgumentList "--disable-warning=ExperimentalWarning `"$report`""
    return
}
& $node.Source --disable-warning=ExperimentalWarning $report
