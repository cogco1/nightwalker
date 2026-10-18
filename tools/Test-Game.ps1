# Full regression: asset import, then every suite in game/tests. Logs: game/evidence/logs.
param([string]$GodotPath = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$godot = Get-NightwalkerGodot $GodotPath
Invoke-NightwalkerImport $godot

$suites = @(
    @{ Name = 'core_v07';                 Script = 'test_v07' },
    @{ Name = 'keybindings';              Script = 'test_keybindings' },
    @{ Name = 'keybindings_reload';       Script = 'test_keybindings'; Extra = @('--', '--reload-profile') },
    @{ Name = 'air_combat';               Script = 'test_air_combat' },
    @{ Name = 'air_dash_animation_v14';   Script = 'test_air_dash_animation_v14' },
    @{ Name = 'scene_integration_v14';    Script = 'test_scene_integration_v14' },
    @{ Name = 'scene_routes';             Script = 'test_scene_routes' },
    @{ Name = 'interior_lighting';        Script = 'test_interior_lighting' },
    @{ Name = 'home_furniture';           Script = 'test_home_furniture' },
    @{ Name = 'hospital_interactions';    Script = 'test_hospital_interactions' },
    @{ Name = 'hospital_environment';     Script = 'test_hospital_environment' },
    @{ Name = 'hospital_physical_stairs'; Script = 'test_hospital_physical_stairs' },
    @{ Name = 'hospital_ward_layout';     Script = 'test_hospital_ward_layout' },
    @{ Name = 'hospital_security';        Script = 'test_hospital_security' },
    @{ Name = 'level_shared';             Script = 'test_level_shared' },
    # Fps: physics/process rate passed as --fixed-fps (default 60); contact_refresh is the high-refresh case.
    @{ Name = 'contact_refresh_v07';      Script = 'test_contact_refresh_v07'; Fps = 144 },
    @{ Name = 'charged_slash';            Script = 'test_charged_slash' },
    @{ Name = 'moveset';                  Script = 'test_moveset' },
    @{ Name = 'combat_state';             Script = 'test_combat_state' },
    @{ Name = 'rhythm_combat';            Script = 'test_rhythm_combat' },
    @{ Name = 'enemy_attack';             Script = 'test_enemy_attack' },
    @{ Name = 'perfect_counter';          Script = 'test_perfect_counter' },
    @{ Name = 'night_street_proto';       Script = 'test_night_street_proto' },
    @{ Name = 'combat_impact_v2';         Script = 'test_combat_impact_v2' },
    @{ Name = 'combat_impact_v2_144';     Script = 'test_combat_impact_v2'; Fps = 144 },
    @{ Name = 'impact_burst';             Script = 'test_impact_burst' },
    @{ Name = 'impact_burst_144';         Script = 'test_impact_burst'; Fps = 144 },
    @{ Name = 'thrust_path';              Script = 'test_thrust_path' },
    @{ Name = 'jump_chase';               Script = 'test_jump_chase' },
    @{ Name = 'jump_chase_144';           Script = 'test_jump_chase'; Fps = 144 },
    @{ Name = 'smooth_charge_links';     Script = 'test_smooth_charge_links' },
    @{ Name = 'smooth_charge_links_144'; Script = 'test_smooth_charge_links'; Fps = 144 },
    @{ Name = 'primary_charge_chain';     Script = 'test_primary_charge_chain' },
    @{ Name = 'primary_charge_chain_144'; Script = 'test_primary_charge_chain'; Fps = 144 },
    @{ Name = 'direct_charge';             Script = 'test_direct_charge' },
    @{ Name = 'direct_charge_144';         Script = 'test_direct_charge'; Fps = 144 },
    @{ Name = 'charged_draw';              Script = 'test_charged_draw' },
    @{ Name = 'charged_draw_144';          Script = 'test_charged_draw'; Fps = 144 },
    @{ Name = 'heavy_cleave';             Script = 'test_heavy_cleave' },
    @{ Name = 'roll_thrust_motion';       Script = 'test_roll_thrust_motion' },
    @{ Name = 'shift_controls';            Script = 'test_shift_controls' },
    @{ Name = 'locomotion_blade';          Script = 'test_locomotion_blade' },
    @{ Name = 'light_sense';              Script = 'test_light_sense' },
    @{ Name = 'coburn_execution';         Script = 'test_coburn_execution' },
    @{ Name = 'coburn_reward_flow';       Script = 'test_coburn_reward_flow' },
    @{ Name = 'chapter_flow';             Script = 'test_chapter_flow' },
    # Enters through boot.tscn at the first night, as Run-Game.ps1 -Step d1_night does.
    @{ Name = 'night_fight';              Script = 'test_night_fight'; Extra = @('--', '--nw-step=d1_night') }
)

$failed = @()
$total = 0
foreach ($suite in $suites) {
    $fps = if ($suite.Fps) { $suite.Fps } else { 60 }
    $arguments = @('--headless', '--fixed-fps', [string]$fps, '--script', ('res://tests/' + $suite.Script + '.gd'))
    if ($suite.Extra) { $arguments += $suite.Extra }
    $result = Invoke-NightwalkerGodot $godot $arguments $suite.Name 300
    $checks = 0
    if ($result.Output -match '"checks":\s*(\d+)') { $checks = [int]$Matches[1] }
    elseif ($result.Output -match 'checks:\s*(\d+)/\d+') { $checks = [int]$Matches[1] }
    $total += $checks
    if ($result.Failed) {
        $failed += $suite.Name
        '{0,-26} FAIL {1,5} checks  exit={2}' -f $suite.Name, $checks, $result.ExitCode
        Get-Content -LiteralPath $result.ErrorLog -Tail 15 -Encoding UTF8 | ForEach-Object { '    ' + $_ }
    } else {
        '{0,-26} ok   {1,5} checks' -f $suite.Name, $checks
    }
}
'-' * 48
'{0} 组，共 {1} 项检查，失败 {2} 组。日志：{3}' -f $suites.Count, $total, $failed.Count, $NightwalkerLogs
if ($failed.Count -gt 0) {
    '失败：' + ($failed -join ', ')
    exit 1
}
