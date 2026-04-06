 <#
.SYNOPSIS
  Bulk DNS check for Azure App Service hostnames using Resolve-DnsName.

.EXAMPLE
  $apps = 'web1','web2','my-full-name.azurewebsites.net'
  .\Test-AzureWebsitesDns.ps1 -Names $apps -Types A,CNAME -OutCsv .\dns-results.csv

.EXAMPLE
  .\Test-AzureWebsitesDns.ps1 -InputFile .\apps.txt -DnsServer 1.1.1.1
#>

[CmdletBinding()]
param(
  # App names or FQDNs. If you pass bare names (no dot), the script appends ".azurewebsites.net".
  [string[]] $Names,

  # Optional file with one name per line (can be bare or FQDN).
  [string]   $InputFile,

  # Suffix to append to bare names.
  [string]   $Suffix = 'azurewebsites.net',

  # Record types to query.
  [ValidateSet('A','AAAA','CNAME','TXT','NS')]
  [string[]] $Types = @('A','AAAA','CNAME'),

  # Optional DNS server to use (e.g., 1.1.1.1 or 8.8.8.8). Default is your system resolver.
  [string]   $DnsServer,

  # Retry count per query on failure.
  [int]      $Retries = 1,

  # Optional CSV path for results.
  [string]   $OutCsv
)

function Normalize-Name {
  param([string]$Name,[string]$Suffix)
  $trim = $Name.Trim()
  if ($trim -match '\.') { $trim } else { "$trim.$Suffix" }
}

function Invoke-DnsQuery {
  param(
    [string] $Fqdn,
    [string] $Type,
    [string] $Server,
    [int]    $Retries
  )
  $params = @{
    Name         = $Fqdn
    Type         = $Type
    ErrorAction  = 'Stop'
    DnsOnly      = $true
    NoHostsFile  = $true
  }
  if ($Server) { $params.Server = $Server }

  $attempt = 0
  do {
    $attempt++
    try {
      return Resolve-DnsName @params
    } catch {
      if ($attempt -le $Retries) {
        Start-Sleep -Milliseconds 200
      } else {
        throw
      }
    }
  } while ($true)
}

# Collect inputs
$allNames = @()
if ($InputFile) {
  if (-not (Test-Path $InputFile)) {
    throw "Input file not found: $InputFile"
  }
  $allNames += Get-Content -Path $InputFile | Where-Object { $_ -and $_.Trim() -ne '' }
}
if ($Names) { $allNames += $Names }

if (-not $allNames) {
  throw "No names provided. Use -Names or -InputFile."
}

# Normalize to FQDNs
$fqdns = $allNames | ForEach-Object { Normalize-Name -Name $_ -Suffix $Suffix } | Select-Object -Unique

$results = New-Object System.Collections.Generic.List[object]

foreach ($fqdn in $fqdns) {
  foreach ($t in $Types) {
    try {
      $sw = [System.Diagnostics.Stopwatch]::StartNew()
      $res = Invoke-DnsQuery -Fqdn $fqdn -Type $t -Server $DnsServer -Retries $Retries
      $sw.Stop()

      # Filter to the Answer section and format answers by type
      $answersRaw = $res | Where-Object Section -eq 'Answer'
      $answers =
        switch ($t) {
          'A'     { ($answersRaw | Where-Object Type -eq 'A'     | ForEach-Object IPAddress) -join ', ' }
          'AAAA'  { ($answersRaw | Where-Object Type -eq 'AAAA'  | ForEach-Object IPAddress) -join ', ' }
          'CNAME' { ($answersRaw | Where-Object Type -eq 'CNAME' | ForEach-Object NameHost) -join ', ' }
          'TXT'   { ($answersRaw | Where-Object Type -eq 'TXT'   | ForEach-Object { $_.Strings -join '' }) -join ' | ' }
          'NS'    { ($answersRaw | Where-Object Type -eq 'NS'    | ForEach-Object NameHost) -join ', ' }
        }

      if (-not $answers) { $answers = '(no answer section)' }

      $ttl = ($answersRaw | Select-Object -First 1 -ExpandProperty TTL -ErrorAction Ignore)

      $results.Add([pscustomobject]@{
        Hostname    = $fqdn
        QueryType   = $t
        ResolvedTo  = $answers
        TTL         = $ttl
        DnsServer   = $(if ($DnsServer) { $DnsServer } else { '(system default)' })
        Status      = 'OK'
        ElapsedMs   = [math]::Round($sw.Elapsed.TotalMilliseconds,0)
        Error       = $null
      })
    } catch {
      $results.Add([pscustomobject]@{
        Hostname    = $fqdn
        QueryType   = $t
        ResolvedTo  = $null
        TTL         = $null
        DnsServer   = $(if ($DnsServer) { $DnsServer } else { '(system default)' })
        Status      = 'FAIL'
        ElapsedMs   = $null
        Error       = $_.Exception.Message
      })
    }
  }
}

# Output
$results | Sort-Object Hostname, QueryType | Format-Table -AutoSize

if ($OutCsv) {
  $results | Sort-Object Hostname, QueryType | Export-Csv -Path $OutCsv -NoTypeInformation -Encoding UTF8
  Write-Host "`nSaved CSV -> $OutCsv" -ForegroundColor Green
} 
