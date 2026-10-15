# Imports assets and starts the game; -Editor opens the Godot editor instead.
param([string]$GodotPath = '', [switch]$Editor)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$godot = Get-NightwalkerGodot $GodotPath
$quotedProject = '"' + $NightwalkerProject + '"'
if ($Editor) {
    Start-Process -FilePath $godot -ArgumentList @('--editor', '--path', $quotedProject) -WorkingDirectory $NightwalkerProject -WindowStyle Normal
    return
}
Invoke-NightwalkerImport $godot
Start-Process -FilePath $godot -ArgumentList @('--path', $quotedProject) -WorkingDirectory $NightwalkerProject -WindowStyle Normal
