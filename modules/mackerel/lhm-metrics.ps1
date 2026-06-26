# LibreHardwareMonitor (data.json) -> Mackerel custom metric plugin.
#
# NOTE: Comments are intentionally ASCII-only. Windows PowerShell 5.1 reads a
# BOM-less file as the system ANSI codepage (CP932 on Japanese Windows), and
# multibyte Japanese bytes corrupt parsing. Japanese rationale lives in the
# home-manager module (hosts/wsl-gentoo.nix) and conf.d/lhm.conf instead.
#
# Executed by the Windows mackerel-agent. Walks the LHM sensor tree and emits
# Mackerel custom-metric lines: <metric_name>\t<value>\t<epoch>
# - Metric name is derived from each sensor's SensorId (unique).
# - Values are unit-suffixed strings ("12.1 V", "38.7 C"); the numeric part only
#   is extracted. Sensors without a numeric reading (e.g. "-") are skipped.
# - On fetch failure (LHM stopped) it exits cleanly with no output.
#
# Filtering keeps the host under Mackerel's 200-metrics-per-host limit:
# - Global: Type in Temperature / Fan / Power / Load (all hardware).
# - Aquacomputer high flow NEXT (USB vendor 0C70 / product F012) water loop:
#   additionally Flow / Level (Water Quality) / Conductivity. Water temperature
#   is already covered by the global Temperature rule.

$ErrorActionPreference = 'Stop'

$Uri = 'http://localhost:8100/data.json'

try {
    $data = Invoke-RestMethod -Uri $Uri -TimeoutSec 5
}
catch {
    exit 0
}

$epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

$GlobalTypes = @('Temperature', 'Fan', 'Power', 'Load')
$WaterPrefix = '/usbhid/0C70/F012'
$WaterTypes = @('Flow', 'Level', 'Conductivity')

function Emit-Node {
    param($node)

    if ($node.SensorId -and ($node.Value -match '-?\d+(\.\d+)?')) {
        $type = $node.Type
        $include = $false
        if ($GlobalTypes -contains $type) {
            $include = $true
        }
        elseif ($node.SensorId.StartsWith($WaterPrefix) -and ($WaterTypes -contains $type)) {
            $include = $true
        }

        if ($include) {
            $value = [regex]::Match($node.Value, '-?\d+(\.\d+)?').Value
            # mackerel-agent prepends "custom." to plugin metric names automatically,
            # so emit "lhm.*" here (NOT "custom.lhm.*") to avoid a doubled "custom." prefix.
            $name = 'lhm' + ($node.SensorId -replace '[^A-Za-z0-9]', '.')
            Write-Output ("{0}`t{1}`t{2}" -f $name, $value, $epoch)
        }
    }

    foreach ($child in $node.Children) {
        Emit-Node $child
    }
}

Emit-Node $data
