"""Audit the supplied character preservation and create a portable integrated source bundle."""
import hashlib
import json
import os
import shutil
import zipfile
from pathlib import Path

BASE = Path(__file__).resolve().parent / 'integration_v14'
OUT = BASE / 'outputs'
GAME = OUT / 'Current_Game'
ORIGINAL = BASE / 'original_v10/Current_Game'
ARCHIVE = OUT / '夜行者_v14_场景融合与独立空中突刺_源码与素材.zip'
SOURCE_BACKUP = OUT / '夜行者_v10_人物工程_修改前备份.zip'
REPORTS = ['test_results_v07.json', 'keybindings_report.json', 'keybindings_reload_report.json',
           'air_combat_report.json', 'air_dash_animation_v14_report.json', 'scene_integration_results_v14.json',
           'hospital_interaction_results_v11.json', 'hospital_test_results_v11.json',
           'hospital_physical_stairs_v11.json', 'hospital_ward_layout_v11_2.json', 'hospital_security_results_v13.json']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def files(root):
    for directory, folders, names in os.walk(root):
        folders[:] = sorted(folder for folder in folders if folder not in {'.godot', '.git', '__pycache__', '.venv'})
        for name in sorted(names):
            if name.startswith('probe_stairs') or name.endswith('.source'):
                continue
            yield Path(directory) / name


def validate():
    results = {name: read(GAME / 'evidence' / name) for name in REPORTS}
    assert all(not result.get('failures') and result.get('status', 'passed') == 'passed' for result in results.values())
    assert results['test_results_v07.json']['observations']['clips'] == 64
    assert results['test_results_v07.json']['observations']['frames'] == 1024
    assert read(GAME / 'art_metadata/air_dash_v14/validation_report.json')['passed']
    old_frames = sorted((ORIGINAL / 'frames').rglob('*.png'))
    assert len(old_frames) == 992
    assert all(sha(path) == sha(GAME / path.relative_to(ORIGINAL)) for path in old_frames)
    assert sha(GAME / 'scenes/player.tscn') == sha(ORIGINAL / 'scenes/player.tscn')
    assert sha(GAME / 'assets/top_down.tres') == sha(ORIGINAL / 'assets/top_down.tres')
    expected_player = (ORIGINAL / 'scripts/player.gd').read_text(encoding='utf-8')
    expected_player = expected_player.replace('\tvar animation := kind + "_" + facing\n',
        '\tvar animation := kind + "_" + facing\n\tif kind == "dash_stab" and not is_on_floor():\n\t\tanimation = "air_dash_stab_" + facing\n')
    assert (GAME / 'scripts/player.gd').read_text(encoding='utf-8') == expected_player
    assert 'arena.gd' not in (GAME / 'scenes/main.tscn').read_text(encoding='utf-8')
    assert not (GAME / 'scripts/arena.gd').exists() and not (GAME / 'scripts/training_target.gd').exists()
    for name in ['clean_import_final_errors.log']:
        assert not (OUT / name).read_text(encoding='utf-8-sig').strip()
    capture = read(GAME / 'evidence/integrated_v14/capture_report.json')
    assert capture['status'] == 'passed' and not capture['combat_fixture_used']
    assert len(capture['frames']) == 256
    assert all(frame['scale'] == [1, 1] and frame['sprite_scale'] == [1, 1] for frame in capture['frames'])
    for name in ['capture_stderr.log']:
        assert not (GAME / 'evidence/integrated_v14' / name).read_text(encoding='utf-8-sig').strip()
    return results


def main():
    results = validate()
    source_manifest = read(BASE / 'input_manifest.json')
    original_zip = BASE / '夜行者_v10_空中突刺衔接_源码与素材.zip'
    assert sha(original_zip) == 'd0ded3047886a3bcb8afcc40b3c37bdd9274c84cab07e404f7e9525e0a0752a9'
    shutil.copy2(original_zip, SOURCE_BACKUP)
    assert sha(SOURCE_BACKUP) == sha(original_zip)
    baseline = BASE / 'baseline_qa/Current_Game/evidence'
    baseline_count = sum(read(baseline / name)['checks'] for name in REPORTS[:4])
    assert baseline_count == 717
    checks = sum(result['checks'] for result in results.values())
    manifest = dict(version='v14', status='passed', engine=(OUT / 'engine_version.txt').read_text(encoding='utf-8-sig').strip(),
        source=source_manifest, baseline_checks=717, current_checks=checks,
        suites={name: result['checks'] for name, result in results.items()}, original_frames_preserved=992,
        new_air_dash_frames=32, animation_clips=64, frames=1024, player_runtime_change_lines=2,
        main_scene='res://scenes/main.tscn', main_behavior='home_601', public_scenes=['home_601', 'underground_hospital'],
        training_entry_removed=True, training_fixture='tests/fixtures/combat_lab.tscn', clean_import='passed',
        actual_project=str(GAME), source_backup=str(SOURCE_BACKUP),
        scene_backup=str(OUT / '夜行者_融合前安全屋医院工程备份.zip'),
        generation_mode='built-in image_gen', prompt_manifest='Current_Game/art_metadata/air_dash_v14/generation_manifest.json',
        gpu_frames=256, gpu_scenes='actual environments, no targets/NPCs', archive=str(ARCHIVE))
    (GAME / 'evidence/qa_summary_v14.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    report = f'''《夜行者》v14 实际运行交付结果
引擎：{manifest['engine']}
项目：{GAME}
原始v10基线：717项检查全部通过。
融合后完整检查：{checks}项，{len(results)}组，失败0。
干净工程导入：退出0，无错误日志；完整Test-Game.ps1退出0。
新增动作：左右各16帧，40fps，112×96，固定足点(56,84)，人物scale=1；总64动作/1024帧。
原992帧、原玩家场景、俯视资源与地面突刺保持；player.gd仅增加两行动画分支。
真实医院录制256帧：左右空突刺→air_idle→空中三连→S下劈→落地；另有安全屋/医院双视角截图。
可玩入口：Run-Demo.cmd；编辑器：Open-Editor.cmd；完整检查：Test-Game.cmd。
正式游戏仅安全屋和医院；E门口/医院出口往返，F7快捷往返；F6训练入口移除。
原717战斗环境仅保存在tests/fixtures，自动测试时使用，不会在正式流程创建训练目标。
医院俯视三门密码1010；电闸需钥匙，后续NPC对话发钥匙，本版不放NPC。
按键配置保留原user://路径；改键后重置位置生效，若F7已被玩家绑定，快捷转场不抢键。
修改前人物备份：{manifest['source_backup']}
修改前场景备份：{manifest['scene_backup']}
新增原画与完整提示词：Current_Game/art_metadata/air_dash_v14，内置image_gen制作。
最终记录：Current_Game/evidence/qa_summary_v14.json及各组日志。
源包：{ARCHIVE}
'''
    (OUT / '空中突刺融合交付结果.txt').write_text(report, encoding='utf-8-sig')
    metadata = GAME / 'art_metadata/air_dash_v14'
    for path in [Path(__file__), BASE.parent / 'merge_scene_sources_v14.py', BASE.parent / 'configure_handoff_v14.py']:
        shutil.copy2(path, metadata / path.name)
    with zipfile.ZipFile(ARCHIVE, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in files(GAME):
            archive.write(path, Path('Current_Game') / path.relative_to(GAME))
        for name in ['Run-Demo.cmd', 'Open-Editor.cmd', 'Test-Game.cmd', 'godot-path.txt', '空中突刺融合交付结果.txt', 'engine_version.txt', 'clean_import_final.log', 'clean_import_final_errors.log']:
            archive.write(OUT / name, name)
    with zipfile.ZipFile(ARCHIVE) as archive:
        assert archive.testzip() is None
        assert sum(name.startswith('Current_Game/frames/') and name.endswith('.png') for name in archive.namelist()) == 1024
    manifest.update(zip_bytes=ARCHIVE.stat().st_size, sha256=sha(ARCHIVE))
    (OUT / 'delivery_v14.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    (OUT / (ARCHIVE.name + '.sha256')).write_text(manifest['sha256']+'  '+ARCHIVE.name+'\n', encoding='utf-8')
    print(json.dumps({'status':'delivered', 'checks':checks, 'zip':str(ARCHIVE), 'bytes':manifest['zip_bytes'], 'sha256':manifest['sha256']}, ensure_ascii=True))


if __name__ == '__main__':
    main()
