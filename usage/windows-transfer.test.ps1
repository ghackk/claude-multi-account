param([Parameter(Mandatory=$true)][string]$FixtureHome)
$ErrorActionPreference = 'Stop'
$fixtureTemp = Join-Path $FixtureHome 'temporary'
New-Item -ItemType Directory -Path $fixtureTemp -Force | Out-Null
$config = Join-Path $FixtureHome '.claude'
New-Item -ItemType Directory -Path $config -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $config '.credentials.json'), '{"claudeAiOauth":{"accessToken":"SYNTHETIC_ONLY"}}')
$identity = Join-Path $FixtureHome '.claude.json'
[System.IO.File]::WriteAllText($identity, '{"oauthAccount":{"emailAddress":"main@example.com"}}')
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '..\claude-menu.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($name in @('Build-ExportToken', 'Apply-ImportToken')) {
    $definition = $ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name}, $true)
    $source = $definition.Extent.Text.Replace('$HOME', '$FixtureHome').Replace('$env:TEMP', '$fixtureTemp')
    . ([scriptblock]::Create($source))
}
function Get-Accounts { [pscustomobject]@{Name='claude';IsDefault=$true} }
function Read-Host { 'y' }
$token = Build-ExportToken 'claude'
if (!$token -or !$token.StartsWith('CLAUDE_TOKEN_GZ:')) { throw 'No default-account export token' }
[System.IO.File]::WriteAllText($identity, '{}')
if (!(Apply-ImportToken $token)) { throw 'Default-account import failed' }
$saved = Get-Content -Raw -LiteralPath $identity | ConvertFrom-Json
if ($saved.oauthAccount.emailAddress -ne 'main@example.com') { throw 'Default-account email was lost' }
Write-Host 'Windows default-account transfer passed'
