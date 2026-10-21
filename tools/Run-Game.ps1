# Imports assets and starts the game at the entry page (scenes/boot.tscn); -Scene starts another scene, e.g.
# res://scenes/main.tscn for the safehouse or res://scenes/night_street_proto.tscn; -Editor opens the Godot editor.
param([string]$GodotPath = '', [switch]$Editor, [string]$Scene = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$godot = Get-NightwalkerGodot $GodotPath
$quotedProject = '"' + $NightwalkerProject + '"'
if ($Editor) {
    Start-Process -FilePath $godot -ArgumentList @('--editor', '--path', $quotedProject) -WorkingDirectory $NightwalkerProject -WindowStyle Normal
    return
}
Invoke-NightwalkerImport $godot
$arguments = @('--path', $quotedProject)
if ($Scene) { $arguments += $Scene }
Start-Process -FilePath $godot -ArgumentList $arguments -WorkingDirectory $NightwalkerProject -WindowStyle Normal
