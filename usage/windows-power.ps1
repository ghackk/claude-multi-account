$ErrorActionPreference = 'Stop'
# Repair existing tasks during background upgrades as well as menu installs.
$task = Get-ScheduledTask -TaskName 'Claude usage history' -ErrorAction SilentlyContinue
if ($task -and ($task.Settings.DisallowStartIfOnBatteries -or $task.Settings.StopIfGoingOnBatteries)) {
    $task.Settings.DisallowStartIfOnBatteries = $false
    $task.Settings.StopIfGoingOnBatteries = $false
    Set-ScheduledTask -InputObject $task | Out-Null
}
