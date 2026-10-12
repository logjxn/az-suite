<#
.SYNOPSIS
    Sends one raw DNS query to a server from each given source address
    and reports which source addresses get a reply

.DESCRIPTION

    Builds a minimal DNS query by hand and sends it over
    UDP from a socket bound to each source address, bypassing the Windows
    DNS Client service. Written to prove why my domain controller's
    resolver timed out

    "Replied" means any UDP response came back

.PARAMETER Server
    DNS server to query. Default: 10.0.0.10 (DC01).

.PARAMETER SourceAddress
    One or more local IP addresses to send the query from

.PARAMETER Name
    Name to look up. Default: example.org.

.PARAMETER TimeoutMs
    How long to wait for each reply, in milliseconds. Default: 2000.

.EXAMPLE
    .\Test-DnsSourceAddress.ps1 -SourceAddress 10.0.0.10, 10.0.2.15
#>
[CmdletBinding()]
param(
    [ipaddress]$Server = '10.0.0.10',

    [Parameter(Mandatory)]
    [ipaddress[]]$SourceAddress,

    [string]$Name = 'example.org',

    [int]$TimeoutMs = 2000
)

# Query = 12-byte header + name as length-prefixed labels + type A + class IN
$header = [byte[]](0x12,0x34, 0x01,0x00, 0x00,0x01, 0,0, 0,0, 0,0)  # ID, recursion desired, 1 question
$qname  = foreach ($label in $Name.TrimEnd('.').Split('.')) {
    [byte]$label.Length
    [Text.Encoding]::ASCII.GetBytes($label)
}
$query = [byte[]]($header + $qname + 0 + (0,1) + (0,1))

foreach ($src in $SourceAddress) {
    $udp = $null
    try {
        $udp = [Net.Sockets.UdpClient]::new([Net.IPEndPoint]::new($src, 0))
        $udp.Client.ReceiveTimeout = $TimeoutMs
        [void]$udp.Send($query, $query.Length, [Net.IPEndPoint]::new($Server, 53))

        $from  = [Net.IPEndPoint]::new([ipaddress]::Any, 0)
        $reply = $udp.Receive([ref]$from)

        [pscustomobject]@{
            Source  = "$src"
            Server  = "$Server"
            Replied = $true
            Detail  = "$($reply.Length) bytes from $from"
        }
    }
    catch {
        $err = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message }
               else { $_.Exception.Message }
        [pscustomobject]@{
            Source  = "$src"
            Server  = "$Server"
            Replied = $false
            Detail  = $err
        }
    }
    finally {
        if ($udp) { $udp.Close() }
    }
}