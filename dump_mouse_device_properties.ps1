# Dump Device Manager / PnP properties for Mice and Bluetooth devices only (keeps output small).
# Output: device_properties_mouse.txt in the script directory.
#
# Run: dump_mouse_device_properties.bat  (or powershell -ExecutionPolicy Bypass -File dump_mouse_device_properties.ps1)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$outFile = Join-Path $scriptDir "device_properties_mouse.txt"
$ErrorActionPreference = "Continue"

# Only Mice and Bluetooth: Device Manager class "Mouse" or "Bluetooth*", or Razer/Basilisk by name/VID
function Get-AllPnPDeviceProperties {
    param([string]$InstanceId)
    $props = @{}
    try {
        $list = Get-PnpDeviceProperty -InstanceId $InstanceId -ErrorAction SilentlyContinue
        foreach ($p in $list) {
            $key = $p.KeyName
            $val = $p.Data
            if ($val -is [byte[]]) { $val = "([byte[]] " + $val.Length + " bytes)" }
            $props[$key] = $val
        }
    } catch {}
    $props
}

function Write-DeviceBlock {
    param($Device, [hashtable]$Props, [System.IO.StreamWriter]$Writer)
    $Writer.WriteLine("")
    $Writer.WriteLine("=" * 78)
    $Writer.WriteLine("InstanceId: $($Device.InstanceId)")
    $Writer.WriteLine("Status: $($Device.Status); Class: $($Device.Class); FriendlyName: $($Device.FriendlyName)")
    $Writer.WriteLine("=" * 78)
    foreach ($k in ($Props.Keys | Sort-Object)) {
        $v = $Props[$k]
        if ($null -eq $v) { $v = "" }
        $Writer.WriteLine("  $k = $v")
    }
}

# Only Mice and Bluetooth devices (no HID/keyboard spill)
$allDevices = Get-PnpDevice -ErrorAction SilentlyContinue
$candidates = $allDevices | Where-Object {
    $c = $_.Class
    $n = $_.FriendlyName
    $id = $_.InstanceId
    # Mouse class = "Mice and other pointing devices"
    ($c -eq "Mouse") -or
    # Bluetooth classes (radios, LE enum, etc.)
    ($c -match "Bluetooth") -or
    # Razer/Basilisk by name or USB VID 1532
    ($n -match "Razer|Basilisk") -or
    ($id -match "Razer|Basilisk|VID_1532")
} | Select-Object -Unique -Property InstanceId

$total = @($candidates).Count
Write-Host "Found $total device(s) that may be the mouse or related. Writing to $outFile"

$sw = [System.IO.StreamWriter]::new($outFile, $false, [System.Text.Encoding]::UTF8)
$sw.WriteLine("Device Manager / PnP property dump - Mice and Bluetooth devices only")
$sw.WriteLine("Output file: " + $outFile)
$sw.WriteLine("Generated: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
$sw.WriteLine("")

foreach ($dev in $candidates) {
    $props = Get-AllPnPDeviceProperties -InstanceId $dev.InstanceId
    Write-DeviceBlock -Device $dev -Props $props -Writer $sw
}

# For each candidate, dump registry subtree (Device Parameters, Driver, etc.)
$sw.WriteLine("")
$sw.WriteLine("--- Registry (HKLM\\SYSTEM\\CurrentControlSet\\Enum\\...) ---")
foreach ($dev in $candidates) {
    $basePath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($dev.InstanceId)"
    if (Test-Path -LiteralPath $basePath -ErrorAction SilentlyContinue) {
        $sw.WriteLine("")
        $sw.WriteLine("Registry: $basePath")
        try {
            $keys = Get-ChildItem -Path $basePath -ErrorAction SilentlyContinue
            foreach ($key in $keys) {
                $sw.WriteLine("  Subkey: $($key.PSChildName)")
                $vals = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
                if ($vals) {
                    $vals.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
                        $v = $_.Value
                        if ($v -is [byte[]]) { $v = "([byte[]] " + $v.Length + " bytes: " + ([BitConverter]::ToString($v)) + ")" }
                        $sw.WriteLine("    $($_.Name) = $v")
                    }
                }
                # Device Parameters, Driver, etc. may be one level down (e.g. 0, 1 for multiple instances)
                Get-ChildItem -Path $key.PSPath -ErrorAction SilentlyContinue | ForEach-Object {
                    $sw.WriteLine("    [Sub] $($_.PSChildName)")
                    $v2 = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
                    if ($v2) {
                        $v2.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
                            $vt = $_.Value
                            if ($vt -is [byte[]]) { $vt = "([byte[]] " + $vt.Length + " bytes)" }
                            $sw.WriteLine("      $($_.Name) = $vt")
                        }
                    }
                }
            }
        } catch { $sw.WriteLine("  (error: $_)") }
    }
}

$sw.Close()
Write-Host "Done. Full dump in $outFile"

# Optional: list device classes and counts (for reference)
Write-Host ""
Write-Host "Device classes in this dump:"
$candidates | Group-Object -Property Class | ForEach-Object { Write-Host "  $($_.Name): $($_.Count)" }
