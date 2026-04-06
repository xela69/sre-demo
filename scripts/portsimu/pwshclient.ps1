$Target = '172.16.110.5'
$TcpPorts = 22,25,53,80,88,123,135,137,139,161,389,443,445,464,636,647,1433,3268,3269,3389,5671,8443,9191,9192,9389,9200,9300,9400,49152,55000,61000
$UdpPorts = 53,123,161,5353,5671,9200,9300,9400,53000

"=== TCP tests to $Target ==="
foreach ($p in $TcpPorts) {
  $r = Test-NetConnection -ComputerName $Target -Port $p -WarningAction SilentlyContinue
  if ($r.TcpTestSucceeded) { "TCP $p  OK" } else { "TCP $p  FAIL" }
}

"=== UDP tests to $Target ==="
function Test-UDP {
  param([string]$Dest,[int]$UdpPort,[int]$TimeoutMs=1000)
  $U = New-Object System.Net.Sockets.UdpClient
  $U.Client.ReceiveTimeout = $TimeoutMs
  $Bytes = [Text.Encoding]::ASCII.GetBytes("hi")
  $U.Send($Bytes,$Bytes.Length,$Dest,$UdpPort) | Out-Null
  try {
    $EP = New-Object System.Net.IPEndPoint([Net.IPAddress]::Any,0)
    $Resp = $U.Receive([ref]$EP)
    $Text = [Text.Encoding]::ASCII.GetString($Resp)
    if ($Text -match "OK\s+$UdpPort") { return $true } else { return $false }
  } catch { return $false } finally { $U.Close() }
}

foreach ($p in $UdpPorts) {
  if (Test-UDP -Dest $Target -UdpPort $p) { "UDP $p  OK" } else { "UDP $p  FAIL" }
}