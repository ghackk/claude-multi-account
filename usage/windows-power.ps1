$ErrorActionPreference = 'Stop'
# Repair existing tasks during background upgrades as well as menu installs.
$task = Get-ScheduledTask -TaskName 'Claude usage history' -ErrorAction SilentlyContinue
if ($task -and ($task.Settings.DisallowStartIfOnBatteries -or $task.Settings.StopIfGoingOnBatteries)) {
    $task.Settings.DisallowStartIfOnBatteries = $false
    $task.Settings.StopIfGoingOnBatteries = $false
    Set-ScheduledTask -InputObject $task | Out-Null
}
# Migrate older tasks off a direct powershell.exe action: Windows Terminal set as the default
# console host causes a visible window flash even with -WindowStyle Hidden. wscript.exe is a
# GUI-subsystem host and is never delegated to Terminal. Test/alternate homes must never run a
# live wscript probe or touch the real scheduled task.
if ($task -and $task.Actions -and $task.Actions[0].Execute -ne 'wscript.exe' -and -not ($env:CLAUDE_USAGE_HOME -or $env:CLAUDE_USAGE_DIR)) {
    $vbs = Join-Path (Split-Path $PSScriptRoot -Parent) 'claude-usage-report-hidden.vbs'
    if (Test-Path $vbs) {
        $wshDisabled = @('HKLM:\SOFTWARE\Microsoft\Windows Script Host\Settings','HKCU:\SOFTWARE\Microsoft\Windows Script Host\Settings') |
            ForEach-Object { (Get-ItemProperty -Path $_ -Name Enabled -ErrorAction SilentlyContinue).Enabled } |
            Where-Object { $_ -eq 0 }
        if (-not $wshDisabled) {
            # Only a working probe earns the migration; a machine where Windows Script Host is
            # blocked keeps the flashy-but-functional direct action rather than silently breaking.
            $probe = Start-Process -FilePath 'wscript.exe' -ArgumentList "//B `"$vbs`"" -PassThru -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
            if ($probe -and $probe.ExitCode -eq 0) {
                $newAction = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "//B `"$vbs`""
                Set-ScheduledTask -TaskName 'Claude usage history' -Action $newAction | Out-Null
            }
        }
    }
}
