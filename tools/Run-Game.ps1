# Imports assets and starts the game (chapter 1 through scenes/boot.tscn); -Scene starts another scene, e.g.
# res://scenes/main.tscn for the free sandbox or res://scenes/night_street_proto.tscn; -DebugKeys keeps F7 / F8 / Tab
# working inside the chapter; -Editor opens the Godot editor instead.
param([string]$GodotPath = '', [switch]$Editor, [string]$Scene = '', [switch]$DebugKeys)
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
if ($DebugKeys) { $arguments += @('--', '--nw-debug') }
Start-Process -FilePath $godot -ArgumentList $arguments -WorkingDirectory $NightwalkerProject -WindowStyle Normal
