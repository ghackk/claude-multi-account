param([Parameter(Mandatory=$true)][string]$Url,[int]$MaxBytes=20971520)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Net.Http
$client=New-Object System.Net.Http.HttpClient
$client.Timeout=[TimeSpan]::FromSeconds(12)
try {
    $response=$client.GetAsync($Url,[System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
    $response.EnsureSuccessStatusCode() | Out-Null
    if ($response.RequestMessage.RequestUri.Scheme -ne 'https') { throw 'HTTPS required' }
    $stream=$response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
    $output=[Console]::OpenStandardOutput();$buffer=New-Object byte[] 65536;$total=0
    while (($length=$stream.Read($buffer,0,$buffer.Length)) -gt 0) {
        $total+=$length;if($total -gt $MaxBytes){throw 'Download too large'}
        $output.Write($buffer,0,$length)
    }
} finally { $client.Dispose() }
