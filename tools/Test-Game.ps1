# Current checks for the empty project; historical suites remain in game/tests/.
param([string]$GodotPath = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$godot = Get-NightwalkerGodot $GodotPath
Invoke-NightwalkerImport $godot
$result = Invoke-NightwalkerGodot $godot @('--headless', '--fixed-fps', '60', '--script', 'res://checks/test_blank_project.gd') 'blank_project' 60
Write-Output $result.Output
if ($result.Failed) {
    Get-Content -LiteralPath $result.ErrorLog -Encoding UTF8
    exit 1
}
