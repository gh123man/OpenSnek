param(
    [Parameter(Mandatory=$true)]
    [string]$Name,

    [int]$Seconds = 20,
    [int]$Port = 24400,
    [string]$BtpRoot = "C:\BTP\v1.14.0",
    [string]$WiresharkRoot = "C:\Program Files\Wireshark",
    [string]$OutRoot = "captures\ble\windows",
    [string]$SynapseLogRoot = "$env:LOCALAPPDATA\Razer\RazerAppEngine\User Data\Logs",
    [double]$CorrelationWindowSeconds = 3,
    [switch]$ReuseBtvs,
    [switch]$KeepBtvs,
    [switch]$ShowBtvs,
    [switch]$NoSynapseLogs
)

$ErrorActionPreference = "Stop"

function Resolve-Tool {
    param([string[]]$Candidates)
    foreach ($candidate in $Candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw "Missing required tool. Checked: $($Candidates -join ', ')"
}

function Test-PortListening {
    param([int]$ListenPort)
    $lines = netstat -ano | Select-String -Pattern (":$ListenPort\s+.*LISTENING")
    return $null -ne $lines
}

function Find-FreePort {
    param([int]$StartPort)

    for ($candidate = $StartPort; $candidate -lt ($StartPort + 200); $candidate++) {
        if (-not (Test-PortListening -ListenPort $candidate)) {
            return $candidate
        }
    }

    throw "Could not find a free BTVS TCP port starting at $StartPort"
}

function Resolve-CapturePort {
    param([int]$RequestedPort)

    if (-not (Test-PortListening -ListenPort $RequestedPort)) {
        return $RequestedPort
    }

    if ($ReuseBtvs) {
        Write-Warning "Reusing existing BTVS listener on port $RequestedPort. This can include buffered/stale packets if BTVS was already running."
        return $RequestedPort
    }

    $freePort = Find-FreePort -StartPort ($RequestedPort + 1)
    Write-Warning "BTVS is already listening on port $RequestedPort; using fresh port $freePort to avoid buffered/stale packets. Use -ReuseBtvs to attach to the existing listener intentionally."
    return $freePort
}

function Hide-ProcessMainWindow {
    param([System.Diagnostics.Process]$Process)

    if ($ShowBtvs) { return }

    if (-not ("OpenSnek.NativeWindow" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace OpenSnek {
    public static class NativeWindow {
        [DllImport("user32.dll")]
        public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
    }
}
"@
    }

    $deadline = (Get-Date).AddSeconds(5)
    while ((Get-Date) -lt $deadline) {
        try {
            $Process.Refresh()
            if ($Process.MainWindowHandle -ne [IntPtr]::Zero) {
                [void][OpenSnek.NativeWindow]::ShowWindowAsync($Process.MainWindowHandle, 0)
                return
            }
        } catch {
            return
        }
        Start-Sleep -Milliseconds 100
    }
}

function Start-BtvsIfNeeded {
    param(
        [string]$Btvs,
        [int]$ListenPort
    )

    if (Test-PortListening -ListenPort $ListenPort) {
        Write-Host "BTVS is already listening on port $ListenPort"
        return $null
    }

    Write-Host "Starting BTVS remote sniffer on port $ListenPort"
    $process = Start-Process -FilePath $Btvs -ArgumentList @("-Mode", "Wireshark", "-Remote", "on", "-Port", "$ListenPort") -WindowStyle Hidden -PassThru
    Hide-ProcessMainWindow -Process $process

    $deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $deadline) {
        if (Test-PortListening -ListenPort $ListenPort) {
            Write-Host "BTVS is listening on port $ListenPort"
            Hide-ProcessMainWindow -Process $process
            return $process
        }
        Start-Sleep -Milliseconds 250
    }

    throw "BTVS did not open TCP port $ListenPort within 10 seconds"
}

function Stop-StartedBtvs {
    param([System.Diagnostics.Process]$Process)

    if ($KeepBtvs -or $null -eq $Process) { return }

    try {
        $Process.Refresh()
        if (-not $Process.HasExited) {
            Write-Host "Stopping BTVS process $($Process.Id)"
            Stop-Process -Id $Process.Id -Force -ErrorAction Stop
        }
    } catch {
        Write-Warning "Could not stop BTVS process $($Process.Id): $($_.Exception.Message)"
        Write-Warning "BTVS can self-elevate on some Windows installs. Close its window manually or run this script from an elevated PowerShell session so cleanup has permission."
    }
}

function Export-AttCsv {
    param(
        [string]$Tshark,
        [string]$Pcap,
        [string]$OutCsv,
        [string]$Filter
    )

    & $Tshark -r $Pcap -Y $Filter -T fields `
        -e frame.number `
        -e frame.time_relative `
        -e btatt.opcode `
        -e btatt.handle `
        -e btatt.value `
        -E header=y `
        -E "separator=," `
        > $OutCsv
}

function Convert-VendorCsvToOperations {
    param([string]$VendorCsv)
    $rows = Import-Csv -LiteralPath $VendorCsv
    $ops = New-Object System.Collections.Generic.List[object]
    $pendingByReq = @{}
    $currentWrite = $null
    $currentNotify = $null

    foreach ($row in $rows) {
        $value = $row.'btatt.value'
        if (-not $value) { continue }

        if ($row.'btatt.handle' -eq "0x003d") {
            if ($null -eq $currentWrite -or $currentWrite.PayloadHex.Length -ge ($currentWrite.Len * 2)) {
                if ($value.Length -ge 16) {
                    $currentWrite = [pscustomobject]@{
                        Frame = $row.'frame.number'
                        Time = $row.'frame.time_relative'
                        Req = $value.Substring(0, 2)
                        Len = [Convert]::ToInt32($value.Substring(2, 2), 16)
                        Key = $value.Substring(8, 8)
                        PayloadHex = ""
                        Status = ""
                        ResponseLen = 0
                        ResponseHex = ""
                    }
                    [void]$ops.Add($currentWrite)
                    $pendingByReq[$currentWrite.Req] = $currentWrite
                    $inlinePayload = $value.Substring(16)
                    if ($inlinePayload.Length -gt 0) {
                        $currentWrite.PayloadHex += $inlinePayload
                    }
                }
            } else {
                $currentWrite.PayloadHex += $value
            }
        } elseif ($row.'btatt.handle' -eq "0x003f") {
            if ($value.Length -ge 16 -and $value.Substring(4, 8) -eq "00000000") {
                $req = $value.Substring(0, 2)
                $status = $value.Substring(14, 2)
                $responseLen = [Convert]::ToInt32($value.Substring(2, 2), 16)
                $match = $pendingByReq[$req]
                if ($match) {
                    $match.Status = $status
                    $match.ResponseLen = $responseLen
                    $currentNotify = $match
                    $inlineResponse = $value.Substring(16)
                    if ($inlineResponse.Length -gt 0) {
                        $match.ResponseHex += $inlineResponse
                    }
                }
            } elseif ($null -ne $currentNotify -and $currentNotify.ResponseHex.Length -lt ($currentNotify.ResponseLen * 2)) {
                $currentNotify.ResponseHex += $value
            }
        }
    }

    return $ops
}

function Shorten-Text {
    param(
        [string]$Value,
        [int]$MaxLength = 220
    )

    if ($null -eq $Value) { return "" }
    $flat = ($Value -replace '\s+', ' ').Trim()
    if ($flat.Length -le $MaxLength) { return $flat }
    return $flat.Substring(0, $MaxLength - 3) + "..."
}

function Write-VendorSummary {
    param(
        [string]$VendorCsv,
        [string]$OutFile
    )

    $ops = Convert-VendorCsvToOperations -VendorCsv $VendorCsv

    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add("# BTVS Capture Summary")
    [void]$lines.Add("")
    [void]$lines.Add("Vendor handles:")
    [void]$lines.Add("- 0x003d: write characteristic")
    [void]$lines.Add("- 0x003f: notify characteristic")
    [void]$lines.Add("- 0x0040: notify CCCD")
    [void]$lines.Add("")
    [void]$lines.Add("| Frame | Time | Req | Len | Key | Payload | Status | Response |")
    [void]$lines.Add("|---:|---:|---|---:|---|---|---|---|")

    foreach ($op in $ops) {
        $payload = if ($op.PayloadHex.Length -gt 0) { $op.PayloadHex.Substring(0, [Math]::Min($op.PayloadHex.Length, $op.Len * 2)) } else { "" }
        $response = if ($op.ResponseHex.Length -gt 0) { $op.ResponseHex.Substring(0, [Math]::Min($op.ResponseHex.Length, $op.ResponseLen * 2)) } else { "" }
        [void]$lines.Add("| $($op.Frame) | $($op.Time) | $($op.Req) | $($op.Len) | ``$($op.Key)`` | ``$payload`` | $($op.Status) | ``$response`` |")
    }

    Set-Content -LiteralPath $OutFile -Value $lines -Encoding UTF8
}

function Export-SynapseEvents {
    param(
        [string]$LogRoot,
        [datetime]$CaptureStart,
        [datetime]$CaptureEnd,
        [string]$OutCsv,
        [string]$OutMarkdown
    )

    $events = New-Object System.Collections.Generic.List[object]
    $csvHeader = '"Time","RelativeSeconds","Source","Line"'
    if (-not (Test-Path -LiteralPath $LogRoot)) {
        Write-Warning "Synapse log root not found: $LogRoot"
        Set-Content -LiteralPath $OutCsv -Value $csvHeader -Encoding UTF8
        Set-Content -LiteralPath $OutMarkdown -Value "# Synapse Events`n`nSynapse log root not found: ``$LogRoot``" -Encoding UTF8
        return $events
    }

    $windowStart = $CaptureStart.AddSeconds(-10)
    $windowEnd = $CaptureEnd.AddSeconds(10)
    $interesting = 'unsupportedmapping|navigateProfile|CycleUp|set active profile|activeProfileGuid|selectedProfileGuid|\[Armory\] Active profile|setSingleButtonMapping|setSingleButtonAssignment|set OBM result|obmSlot|obmData|addProfile|deleteProfile|renameProfile|deviceSwitchProfile'
    $logFiles = Get-ChildItem -LiteralPath $LogRoot -File -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.Name -like 'products_170_mw*' -or
             $_.Name -like 'products_170_ui*' -or
             $_.Name -like 'profiles*' -or
             $_.Name -like 'mapping_engine*') -and
            $_.LastWriteTime -ge $CaptureStart.AddMinutes(-15)
        }

    foreach ($log in $logFiles) {
        Select-String -LiteralPath $log.FullName -Pattern $interesting -CaseSensitive:$false -ErrorAction SilentlyContinue |
            ForEach-Object {
                $line = $_.Line
                $match = [regex]::Match($line, '^\[(?<ts>\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}\.\d{3})\]')
                if (-not $match.Success) { return }
                $eventTime = [datetime]::ParseExact($match.Groups['ts'].Value, 'yyyy/MM/dd HH:mm:ss.fff', [Globalization.CultureInfo]::InvariantCulture)
                if ($eventTime -lt $windowStart -or $eventTime -gt $windowEnd) { return }
                $relative = [Math]::Round(($eventTime - $CaptureStart).TotalSeconds, 3)
                [void]$events.Add([pscustomobject]@{
                    Time = $eventTime.ToString('yyyy-MM-dd HH:mm:ss.fff')
                    RelativeSeconds = $relative
                    Source = $log.Name
                    Line = Shorten-Text -Value $line -MaxLength 2000
                })
            }
    }

    $sorted = @($events | Sort-Object RelativeSeconds, Source)
    if ($sorted.Count -gt 0) {
        $sorted | Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding UTF8
    } else {
        Set-Content -LiteralPath $OutCsv -Value $csvHeader -Encoding UTF8
    }

    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add("# Synapse Events")
    [void]$lines.Add("")
    [void]$lines.Add("Capture start: ``$($CaptureStart.ToString('yyyy-MM-dd HH:mm:ss.fff'))``")
    [void]$lines.Add("")
    [void]$lines.Add("| Rel s | Time | Source | Event |")
    [void]$lines.Add("|---:|---|---|---|")
    foreach ($event in $sorted) {
        $text = (Shorten-Text -Value $event.Line -MaxLength 300).Replace('|', '\|')
        [void]$lines.Add("| $($event.RelativeSeconds) | $($event.Time) | ``$($event.Source)`` | $text |")
    }
    if ($sorted.Count -eq 0) {
        [void]$lines.Add("| | | | No matching Synapse events found in the capture window. |")
    }
    Set-Content -LiteralPath $OutMarkdown -Value $lines -Encoding UTF8

    return $sorted
}

function Write-CorrelationSummary {
    param(
        [string]$VendorCsv,
        [object[]]$SynapseEvents,
        [double]$WindowSeconds,
        [string]$OutFile
    )

    $ops = Convert-VendorCsvToOperations -VendorCsv $VendorCsv
    $interestingOps = $ops | Where-Object { $_.Key -ne "10040000" }
    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add("# Synapse / Packet Correlation")
    [void]$lines.Add("")
    [void]$lines.Add("Window: +/- $WindowSeconds seconds around each Synapse event.")
    [void]$lines.Add("Periodic `10 04 00 00` lighting-frame writes are omitted.")
    [void]$lines.Add("")

    if ($SynapseEvents.Count -eq 0) {
        [void]$lines.Add("No Synapse events matched the capture window. Use `summary.md` for packet-only analysis.")
        Set-Content -LiteralPath $OutFile -Value $lines -Encoding UTF8
        return
    }

    foreach ($event in $SynapseEvents) {
        $eventTime = [double]$event.RelativeSeconds
        $nearby = $interestingOps | Where-Object { [Math]::Abs(([double]$_.Time) - $eventTime) -le $WindowSeconds }
        if ($nearby.Count -eq 0) { continue }

        [void]$lines.Add("## t=$eventTime s")
        [void]$lines.Add("")
        [void]$lines.Add("Synapse: $(Shorten-Text -Value $event.Line -MaxLength 500)")
        [void]$lines.Add("")
        [void]$lines.Add("| Frame | Rel s | Req | Len | Key | Payload | Status | Response |")
        [void]$lines.Add("|---:|---:|---|---:|---|---|---|---|")
        foreach ($op in $nearby) {
            $payload = if ($op.PayloadHex.Length -gt 0) { $op.PayloadHex.Substring(0, [Math]::Min($op.PayloadHex.Length, $op.Len * 2)) } else { "" }
            $response = if ($op.ResponseHex.Length -gt 0) { $op.ResponseHex.Substring(0, [Math]::Min($op.ResponseHex.Length, $op.ResponseLen * 2)) } else { "" }
            [void]$lines.Add("| $($op.Frame) | $($op.Time) | $($op.Req) | $($op.Len) | ``$($op.Key)`` | ``$(Shorten-Text -Value $payload -MaxLength 120)`` | $($op.Status) | ``$(Shorten-Text -Value $response -MaxLength 120)`` |")
        }
        [void]$lines.Add("")
    }

    while ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq "") {
        $lines.RemoveAt($lines.Count - 1)
    }

    Set-Content -LiteralPath $OutFile -Value $lines -Encoding UTF8
}

$btvs = Resolve-Tool @(
    (Join-Path $BtpRoot "x86\btvs.exe"),
    "$env:USERPROFILE\OneDrive\Desktop\v1.14.0\x86\btvs.exe"
)
$tshark = Resolve-Tool @(
    (Join-Path $WiresharkRoot "tshark.exe")
)
$capturePort = Resolve-CapturePort -RequestedPort $Port

$safeName = $Name -replace '[^A-Za-z0-9._-]', '-'
$stamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
$outDir = Join-Path $OutRoot "$stamp-$safeName"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$pcap = Join-Path $outDir "capture.pcapng"
$attCsv = Join-Path $outDir "att.csv"
$vendorCsv = Join-Path $outDir "vendor-att.csv"
$summary = Join-Path $outDir "summary.md"
$metadata = Join-Path $outDir "metadata.json"
$synapseCsv = Join-Path $outDir "synapse-events.csv"
$synapseMarkdown = Join-Path $outDir "synapse-events.md"
$correlation = Join-Path $outDir "correlation.md"

$startedBtvs = $null
try {
    $startedBtvs = Start-BtvsIfNeeded -Btvs $btvs -ListenPort $capturePort

    Write-Host "Capturing BTVS TCP stream for $Seconds seconds into $pcap"
    $captureStart = Get-Date
    & $tshark -i "TCP@127.0.0.1:$capturePort" -a "duration:$Seconds" -w $pcap
    $captureEnd = Get-Date

    Export-AttCsv -Tshark $tshark -Pcap $pcap -OutCsv $attCsv -Filter "btatt"
    Export-AttCsv -Tshark $tshark -Pcap $pcap -OutCsv $vendorCsv -Filter "btatt.handle == 0x003d || btatt.handle == 0x003f || btatt.handle == 0x0040"
    Write-VendorSummary -VendorCsv $vendorCsv -OutFile $summary

    [pscustomobject]@{
        name = $Name
        captureStart = $captureStart.ToString("o")
        captureEnd = $captureEnd.ToString("o")
        seconds = $Seconds
        port = $capturePort
        requestedPort = $Port
        pcap = $pcap
        attCsv = $attCsv
        vendorCsv = $vendorCsv
        synapseLogRoot = $SynapseLogRoot
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $metadata -Encoding UTF8

    if (-not $NoSynapseLogs) {
        $events = Export-SynapseEvents -LogRoot $SynapseLogRoot -CaptureStart $captureStart -CaptureEnd $captureEnd -OutCsv $synapseCsv -OutMarkdown $synapseMarkdown
        Write-CorrelationSummary -VendorCsv $vendorCsv -SynapseEvents @($events) -WindowSeconds $CorrelationWindowSeconds -OutFile $correlation
    }

    Write-Host "Capture complete:"
    Write-Host "  $pcap"
    Write-Host "  $attCsv"
    Write-Host "  $vendorCsv"
    Write-Host "  $summary"
    Write-Host "  $metadata"
    if (-not $NoSynapseLogs) {
        Write-Host "  $synapseCsv"
        Write-Host "  $synapseMarkdown"
        Write-Host "  $correlation"
    }
} finally {
    Stop-StartedBtvs -Process $startedBtvs
}
