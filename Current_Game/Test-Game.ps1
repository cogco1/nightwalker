param([string]$GodotPath = '')
$ErrorActionPreference = 'Stop'
if (-not $GodotPath) {
    $GodotPath = (Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'godot-path.txt') -Raw -Encoding UTF8).Trim().Trim('"')
}
& (Join-Path $PSScriptRoot 'Run-Game.ps1') -GodotPath $GodotPath -Test -BindingsTest -AirTest
foreach ($suite in @('test_air_dash_animation_v14','test_scene_integration_v14','test_hospital_interactions','test_hospital_environment','test_hospital_physical_stairs','test_hospital_ward_layout','test_hospital_security')) {
    $outLog = Join-Path $PSScriptRoot ('evidence/' + $suite + '_v14.log')
    $errLog = Join-Path $PSScriptRoot ('evidence/' + $suite + '_errors_v14.log')
    $quotedProject = '"' + $PSScriptRoot + '"'
    $process = Start-Process -FilePath $GodotPath -ArgumentList @('--headless','--fixed-fps','60','--path',$quotedProject,'--script',('res://tests/' + $suite + '.gd')) -WindowStyle Hidden -PassThru -Wait -RedirectStandardOutput $outLog -RedirectStandardError $errLog
    Get-Content -LiteralPath $outLog
    Get-Content -LiteralPath $errLog
    if ($process.ExitCode -ne 0 -or (Select-String -LiteralPath $errLog -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet)) {
        throw ('Regression failed: ' + $suite)
    }
}
