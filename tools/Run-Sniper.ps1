param([string]$GodotPath = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$godot = Get-NightwalkerGodot $GodotPath
Invoke-NightwalkerImport $godot
& $godot --path $NightwalkerProject res://scenes/sniper_combat_test.tscn
