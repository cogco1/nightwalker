"""Verify and package the selected enemy animation delivery."""
from pathlib import Path
import hashlib
import json
import shutil
import zipfile

from PIL import Image

SCRIPT = Path(__file__).resolve()
ROOT = SCRIPT.parents[2] if SCRIPT.parent.name == 'evidence' else SCRIPT.parents[1]
OUT = ROOT / 'outputs/enemy_animations_v01'
GAME = ROOT / 'game'
EVIDENCE = GAME / 'evidence/enemy_animation_gallery'
BACKUP = Path('E:/CodexWorkspace/Nightwalker_Backups/夜行者_敌人动作制作前_2026-10-21_概念v01.zip')


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')


def copy(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)


def prepare():
    manifest = read(GAME / 'assets/enemy_animations_v01/manifest.json')
    preview = read(OUT / 'preview_validation.json')
    visual = read(OUT / 'visual_review.json')
    headless = read(EVIDENCE / 'headless_report.json')
    gpu = read(EVIDENCE / 'gpu_report.json')
    assert preview['passed'] and preview['actions'] == 18 and preview['frames'] == 144
    assert visual['passed'] and visual['visual_review_complete']
    assert preview['gif_decoded_pixel_match'] and preview['gif_delays_match']
    reviewed_frames = {record['unit'] + '/' + record['action']: record['frame_sha256']
                       for record in preview['actions_detail']}
    assert visual['reviewed_frame_sha256'] == reviewed_frames, 'Art changed after visual review'
    assert headless['passed'] and not headless['failures']
    assert (headless['units'], headless['actions'], headless['native_action_frames']) == (8, 18, 144)
    assert gpu['passed'] and not gpu['headless'] and gpu['screenshots'] == 152
    assert gpu['viewport'] == [320, 180] and gpu['scale'] == 1
    for unit in gpu['units']:
        for action in unit['actions']:
            assert action['frames'] == 8 and len(action['captures']) == 8
            for capture in action['captures']:
                path = GAME / capture.removeprefix('res://')
                assert Image.open(path).size == (320, 180), path
        assert Image.open(EVIDENCE / (unit['unit'] + '_left.png')).size == (320, 180)
    project = OUT / 'preview_project'
    shutil.copytree(GAME / 'assets/enemy_animations_v01', project / 'assets/enemy_animations_v01', dirs_exist_ok=True)
    for relative in ['scripts/enemy_animation_gallery.gd', 'scenes/enemy_animation_gallery.tscn',
                     'scripts/ui/pixel_ui.gd', 'assets/ui/hero_portrait.png']:
        source = GAME / relative
        copy(source, project / relative)
        if source.with_suffix(source.suffix + '.uid').exists():
            copy(source.with_suffix(source.suffix + '.uid'), project / (relative + '.uid'))
        if source.with_suffix(source.suffix + '.import').exists():
            copy(source.with_suffix(source.suffix + '.import'), project / (relative + '.import'))
    shutil.copytree(GAME / 'assets/fonts', project / 'assets/fonts', dirs_exist_ok=True)
    (project / 'project.godot').write_text('''config_version=5

[application]
config/name="夜行者 · 选定敌人动作预览 v01"
run/main_scene="res://scenes/enemy_animation_gallery.tscn"
config/features=PackedStringArray("4.7", "GL Compatibility")

[display]
window/size/viewport_width=320
window/size/viewport_height=180
window/size/window_width_override=1280
window/size/window_height_override=720
window/stretch/mode="viewport"
window/stretch/aspect="keep"
window/stretch/scale_mode="integer"

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
textures/canvas_textures/default_texture_filter=0
2d/snap/snap_2d_transforms_to_pixel=true
2d/snap/snap_2d_vertices_to_pixel=true
''', encoding='utf-8', newline='\n')
    command = '''@echo off
chcp 65001 >nul
setlocal
set "ENEMY_GODOT=%~1"
if not defined ENEMY_GODOT set "ENEMY_GODOT=D:\\浏览器下载\\Godot_v4.7.2-stable_win64.exe\\Godot_v4.7.2-stable_win64.exe"
if not exist "%ENEMY_GODOT%" (
  echo Godot executable was not found.
  echo Drag Godot.exe onto this .cmd, or run: Open-Enemy-Gallery.cmd "C:\\path\\Godot.exe"
  pause
  exit /b 1
)
start "" /wait "%ENEMY_GODOT%" --headless --editor --path "%~dp0preview_project" --import --quit
if errorlevel 1 (
  echo Godot import failed. Please open preview_project/project.godot in the editor for diagnostics.
  pause
  exit /b 1
)
start "" "%ENEMY_GODOT%" --path "%~dp0preview_project" --resolution 1280x720
'''
    (OUT / 'Open-Enemy-Gallery.cmd').write_bytes(command.replace('\n', '\r\n').encode('utf-8'))
    source = OUT / 'source_code'
    for path in sorted((ROOT / 'tools').glob('*enemy_animation*.py')):
        copy(path, source / 'tools' / path.name)
    for relative in ['scripts/enemy_animation_gallery.gd', 'scenes/enemy_animation_gallery.tscn',
                     'tests/test_enemy_animation_gallery.gd', 'tests/support/isolated_suite.gd']:
        path = GAME / relative
        copy(path, source / 'game' / relative)
        if path.with_suffix(path.suffix + '.uid').exists():
            copy(path.with_suffix(path.suffix + '.uid'), source / 'game' / (relative + '.uid'))
    copy(Path(__file__), source / 'tools/package_enemy_animations_v01.py')
    verifier = EVIDENCE / 'verify_gpu_pixels.py'
    if verifier.exists():
        copy(verifier, source / 'game/evidence/enemy_animation_gallery/verify_gpu_pixels.py')
    for path in EVIDENCE.rglob('*'):
        if path.is_file() and path.suffix in {'.json', '.log', '.png'}:
            copy(path, OUT / 'run_test_evidence' / path.relative_to(EVIDENCE))
    assert BACKUP.is_file()
    with zipfile.ZipFile(BACKUP) as archive:
        assert archive.testzip() is None
    write(OUT / 'backup_info.json', {'path': str(BACKUP), 'bytes': BACKUP.stat().st_size,
                                    'crc': 'passed', 'sha256': hashlib.sha256(BACKUP.read_bytes()).hexdigest()})
    action_names = {'hover':'悬浮巡航', 'laser':'激光蓄能与发射', 'walk':'行走', 'fire':'开火',
                    'attack':'近战攻击', 'prone_down':'卧倒', 'prone_crawl':'匍匐移动', 'prone_fire':'卧姿狙击'}
    rows = []
    for unit in manifest['units']:
        actions = '、'.join(action_names[a['name']] for a in unit['actions'])
        variant = unit['unit'].rsplit('_', 1)[-1]
        rows.append(f"| {unit['code']} | {unit['callsign']} {variant} | {unit['name']} | {actions} |")
    readme = '''# 夜行者 · 选定敌人与动作素材 v01

本包包含 8 个选定造型、18 组独立动作、144 帧新绘原生像素动画，以及可直接打开的 Godot 4 动作预览工程。

## 选型与动作

| 代号 | 造型 | 兵种 | 新绘动作 |
| --- | --- | --- | --- |
''' + '\n'.join(rows) + '''

折刃采用第三款 C，重锤兵“碎砧”采用第一款 A，牵线采用第二款 B；其余选型为浮游炮 B、狙击兵 B、步枪兵 A/C、盾卫 B。

每组动作有 8 帧。狙击兵另有卧倒、匍匐移动和卧姿射击；起身复用卧倒的倒序帧，卧姿待机复用卧倒末帧。

## 查看与运行

直接看 `selected_overview.png`、`action_overview.gif`，或进入 `previews/<兵种>/` 查看各动作 GIF 与逐帧接触表。

使用 Godot 4.7.2 打开 `preview_project/project.godot` 后运行。Windows 也可将 Godot.exe 拖到 `Open-Enemy-Gallery.cmd` 上。

- 左右方向键或 1—8：切换兵种。
- 上下方向键：切换动作。
- A / D：向左右移动，并播放行走 / 匍匐 / 悬浮动作。
- F：播放攻击；站立的狙击兵先卧倒再开枪。
- S：狙击兵卧倒或起身。
- 空格：暂停 / 继续；Esc：退出。

预览工程为独立的动画查看器。游戏主入口与原有场景保持原文件内容。

## 素材规格

原生格为 96×64 像素，足点锚为 (48, 57)，人形维持约 32 原生像素的高度。宽格为长枪、卧姿与武器挥动留出透明空间；人物没有扩大。每个动作使用 4×2 排列的 384×128 PNG，独立帧位于 `frames/<兵种>/<动作>/00.png` 至 `07.png`。Alpha 为 0 / 255，固定调色板，最近邻整数放大。

行走 / 悬浮 / 匍匐为循环动作，开火 / 攻击 / 卧倒为单次动作。准确 fps 与循环设置见 `manifest.json`；GIF 为便于检查会重复，单次动作末帧多停留 0.4 秒。左朝向由 Godot `flip_h` 从右朝向原帧镜像，固定相同足点。

## 内容目录

- `selected/`：从原设定集中单独领出的选型、原画细节与参考。
- `source_art/` 与 `generation_prompts.json`：内置 imagegen 新绘原图、完整提示词与生成记录。
- `asset_images/` 与 `frames/`：原生动作图集和独立帧。
- `previews/`：最近邻放大的 GIF 和逐帧对照图。
- `preview_project/`：含 SpriteFrames 的独立 Godot 预览工程与字体许可。
- `source_code/`：图像归一化、预览、Godot 资源生成和验证源码。
- `run_test_evidence/`：实际 Godot 无窗口检查、152 张 GPU 逐帧与左右朝向截图、运行输出。
- `visual_review.json`、`preview_validation.json`：素材与视觉检查结果。
- `file_manifest.json`：包内文件 SHA-256 清单。
- `backup_info.json`：修改前完整备份的路径、CRC 与 SHA-256；备份作为独立文件保存。

使用本轮源码继续制作时，可先把 `source_code/` 中的对应文件复制进 GitHub 完整项目，再按生成脚本中的默认项目路径运行。Python 素材脚本使用 Python 3、Pillow 与 NumPy；Godot 运行预览无需 Python。图片生成使用内置 imagegen；本地程序仅做授权的分帧、像素对齐、调色板归一化与预览合成。
'''
    (OUT / 'README.md').write_text(readme, encoding='utf-8', newline='\n')
    print(json.dumps({'prepared': True, 'preview_project': str(project)}, ensure_ascii=True))


def finish():
    standalone = read(OUT / 'standalone_validation.json')
    assert standalone['passed']
    text_suffixes = {'.json', '.txt', '.md', '.py', '.gd', '.tscn', '.tres', '.import', '.godot', '.svg', '.log', '.uid'}
    for path in OUT.rglob('*'):
        if path.is_file() and path.suffix in text_suffixes:
            path.write_bytes(path.read_bytes().replace(b'\r\n', b'\n'))
    files = {str(path.relative_to(OUT)).replace('\\', '/'): hashlib.sha256(path.read_bytes()).hexdigest()
             for path in sorted(OUT.rglob('*')) if path.is_file()
             and path.name != 'file_manifest.json' and '.godot' not in path.relative_to(OUT).parts
             and path.relative_to(OUT).parts[:2] != ('preview_project', 'evidence')}
    write(OUT / 'file_manifest.json', files)
    target = ROOT / 'outputs/夜行者_选定敌人与动作素材_v01.zip'
    with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for name in files:
            archive.write(OUT / name, name)
        archive.write(OUT / 'file_manifest.json', 'file_manifest.json')
    with zipfile.ZipFile(target) as archive:
        assert archive.testzip() is None
        for name, digest in files.items():
            assert hashlib.sha256(archive.read(name)).hexdigest() == digest, name
    report = {'archive': str(target), 'bytes': target.stat().st_size, 'files': len(files) + 1,
              'archive_sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
              'crc': 'passed', 'manifest_sha256': 'passed', 'units': 8, 'actions': 18,
              'native_animation_frames': 144, 'gpu_frame_captures': 152,
              'focused_checks': read(EVIDENCE / 'headless_report.json')['checks'], 'standalone': standalone}
    write(GAME / 'evidence/enemy_animations_package_result.json', report)
    print(json.dumps(report, ensure_ascii=True))


if __name__ == '__main__':
    import sys
    if '--finish' in sys.argv:
        finish()
    else:
        prepare()
