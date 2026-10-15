"""Bring environment scenes into the supplied character project, without old character assets."""
import shutil
from pathlib import Path

BASE = Path(__file__).resolve().parent
SCENES = BASE / 'game_v11'
GAME = BASE / 'integration_v14/outputs/Current_Game'
ORIGINAL = BASE / 'integration_v14/original_v10/Current_Game'
for name in ['home_601', 'underground_hospital', 'ui', 'fonts']:
    shutil.copytree(SCENES / 'assets' / name, GAME / 'assets' / name, dirs_exist_ok=True)
for name in ['home_601.gd', 'home_prop_fx.gd', 'hospital_interactions.gd', 'hospital_security.gd',
             'pixel_ui.gd', 'story_state.gd', 'underground_hospital.gd', 'scene_routes.gd']:
    shutil.copy2(SCENES / 'scripts' / name, GAME / 'scripts' / name)
for name in ['home_601.tscn', 'underground_hospital.tscn']:
    shutil.copy2(SCENES / 'scenes' / name, GAME / 'scenes' / name)
for name in ['test_hospital_interactions.gd', 'test_hospital_environment.gd', 'test_hospital_physical_stairs.gd',
             'test_hospital_ward_layout.gd', 'test_hospital_security.gd']:
    shutil.copy2(SCENES / 'tests' / name, GAME / 'tests' / name)
for name in ['underground_hospital_v11', 'dialogue_ui_v12', 'hospital_security_v13']:
    source = SCENES / 'art_metadata' / name
    if source.exists():
        shutil.copytree(source, GAME / 'art_metadata' / name, dirs_exist_ok=True)
fixtures = GAME / 'tests/fixtures'
fixtures.mkdir(parents=True, exist_ok=True)
for name in ['arena.gd', 'training_target.gd']:
    shutil.copy2(ORIGINAL / 'scripts' / name, fixtures / name)
lab = (ORIGINAL / 'scenes/main.tscn').read_text(encoding='utf-8')
lab = lab.replace('res://scripts/arena.gd', 'res://tests/fixtures/arena.gd')
(fixtures / 'combat_lab.tscn').write_text(lab, encoding='utf-8')
arena = fixtures / 'arena.gd'
arena.write_text(arena.read_text(encoding='utf-8').replace('res://scripts/training_target.gd',
    'res://tests/fixtures/training_target.gd'), encoding='utf-8')
# Test fixtures remain available only to regression scripts, never scene routes.
for path in (GAME / 'tests').glob('*.gd'):
    if path.name in {'test_air_dash_animation_v14.gd', 'test_scene_integration_v14.gd'}:
        continue
    text = path.read_text(encoding='utf-8-sig')
    text = text.replace('res://scenes/main.tscn', 'res://tests/fixtures/combat_lab.tscn')
    text = text.replace('res://scripts/training_target.gd', 'res://tests/fixtures/training_target.gd')
    path.write_text(text, encoding='utf-8')
test = GAME / 'tests/test_v07.gd'
text = test.read_text(encoding='utf-8')
text = text.replace('String(animation).begins_with("air_") or String(animation).begins_with("dive_slash_")',
    '(String(animation).begins_with("air_") and not String(animation).begins_with("air_dash_stab_")) or String(animation).begins_with("dive_slash_")')
text = text.replace('clip_count == 62 and frame_count == 992', 'clip_count == 64 and frame_count == 1024')
text = text.replace('62 clips and992 imported frames', '64 clips and1024 imported frames')
test.write_text(text, encoding='utf-8')
# Public main entry is now the safehouse; player.tscn stays exactly the supplied version.
(GAME / 'scenes/main.tscn').write_text('[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://scripts/home_601.gd" id="1"]\n\n[node name="NightwalkerHome" type="Node2D"]\nscript = ExtResource("1")\n', encoding='utf-8')
project = GAME / 'project.godot'
text = project.read_text(encoding='utf-8')
text += '\n[autoload]\nSceneRoutes="*res://scripts/scene_routes.gd"\n'
project.write_text(text, encoding='utf-8')
controls = GAME / 'scripts/controls.gd'
controls.write_text(controls.read_text(encoding='utf-8').replace('重置训练场', '重置位置'), encoding='utf-8')
print('Merged environments; supplied player/resources retained, public main becomes home')
