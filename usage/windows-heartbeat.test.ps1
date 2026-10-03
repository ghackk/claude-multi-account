param([Parameter(Mandatory=$true)][string]$FixtureHome)
$ErrorActionPreference='Stop'
$env:MULTI_CLAUDE_REPORT_URL='http://127.0.0.1:9/api/report'
$env:MULTI_CLAUDE_AUTO_UPDATE='0'
$env:CLAUDE_USAGE_HOME=$FixtureHome
$env:CLAUDE_USAGE_DIR=Join-Path $FixtureHome 'history'
$env:CLAUDE_CONFIG_DIR=''
$script:registered=$false
function New-ScheduledTaskAction { param($Execute,$Argument) return @{Execute=$Execute;Argument=$Argument} }
function New-ScheduledTaskTrigger { param([switch]$Once,$At,$RepetitionInterval) return @{Interval=$RepetitionInterval} }
function New-ScheduledTaskSettingsSet { param([switch]$Hidden,[switch]$StartWhenAvailable,$MultipleInstances,$ExecutionTimeLimit) return @{} }
function Register-ScheduledTask {
 param($TaskName,$Action,$Trigger,$Settings,[switch]$Force)
 if($TaskName -ne 'Claude usage history' -or $Trigger.Interval.TotalMinutes -ne 15 -or -not $Force) { throw 'Existing heartbeat was not replaced with a 15-minute schedule' }
 $script:registered=$true
}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$source=[IO.File]::ReadAllText((Join-Path $root 'claude-usage-report.ps1')).Replace('$PSScriptRoot',("'"+$root.Replace("'","''")+"'")).Replace('$HOME','$FixtureHome')
& ([scriptblock]::Create($source)) -Install
if(-not $script:registered) { throw 'Scheduler registration missing' }
foreach($file in @('sharing.js','version.js','report.js')) {
 if(!(Test-Path (Join-Path $FixtureHome "claude-accounts\usage\$file"))) { throw "Installed companion missing: $file" }
}
Write-Host '15-minute heartbeat upgrade and installed reporter companions verified without touching real scheduled tasks.'
