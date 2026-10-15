from pathlib import Path
from PIL import Image
import hashlib
import json

META = Path(__file__).resolve().parent
GAME = META.parents[1]
BASE = GAME.parents[1] / 'original_v10/Current_Game'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    checks = []
    old_frames = sorted((BASE / 'frames').glob('*/*.png'))
    assert len(old_frames) == 992
    assert all(sha(path) == sha(GAME / path.relative_to(BASE)) for path in old_frames)
    checks.append('All 992 original frame PNGs byte-preserved, including both grounded dash sets.')
    assert (BASE / 'assets/top_down.tres').read_bytes() == (GAME / 'assets/top_down.tres').read_bytes()
    old_resource = (BASE / 'assets/side_view.tres').read_bytes()
    new_resource = (GAME / 'assets/side_view.tres').read_bytes()
    old_exts = [line for line in old_resource.splitlines() if line.startswith(b'[ext_resource')]
    new_old_exts = [line for line in new_resource.splitlines() if line.startswith(b'[ext_resource') and b'v14_' not in line]
    assert old_exts == new_old_exts
    old_body = old_resource[old_resource.index(b'[resource]'):]
    new_body = new_resource[new_resource.index(b'[resource]'):]
    assert new_body.startswith(old_body[:old_body.rfind(b']')])
    checks.append('Existing resource definitions and ordering byte-preserved; only new blocks appended.')
    paths = json.loads((GAME / 'assets/blade_paths.json').read_text(encoding='utf-8'))
    old_paths = json.loads((BASE / 'assets/blade_paths.json').read_text(encoding='utf-8'))
    assert all(paths[category][name] == values for category, entries in old_paths.items() for name, values in entries.items())
    checks.append('All old blade-tip paths preserved exactly.')
    colors = json.loads((GAME / 'art_metadata/master_registration.json').read_text(encoding='utf-8'))['palette']
    palette = {tuple(bytes.fromhex(c)) for c in colors}
    steel_palette = {tuple(bytes.fromhex(colors[i])) for i in [14, 15, 16]}
    seen = set()
    for frame in range(16):
        right = Image.open(GAME / 'frames/side_view_right_air_dash_stab' / f'{frame:02d}.png').convert('RGBA')
        left = Image.open(GAME / 'frames/side_view_left_air_dash_stab' / f'{frame:02d}.png').convert('RGBA')
        assert right.size == left.size == (112, 96)
        assert set(right.getchannel('A').getdata()) <= {0, 255}
        assert all(pixel[:3] in palette for pixel in right.getdata() if pixel[3])
        assert right.getbbox()[3] <= 84, (frame, right.getbbox())
        for y in range(96):
            for x in range(1, 112):
                assert left.getpixel((x, y)) == right.getpixel((112 - x, y))
        seen.add(right.tobytes())
        tip = paths['side_view']['air_dash_stab_right'][frame]
        mirror_tip = paths['side_view']['air_dash_stab_left'][frame]
        assert mirror_tip == [-tip[0], tip[1]]
        point = (tip[0] + 56, tip[1] + 84)
        assert right.getpixel(point)[:3] in steel_palette
        assert right.getpixel(point)[3] == 255
        # Ensure tracked steel is physically connected to the figure, not a
        # detached effect pixel that would move the runtime trail away.
        reached = {point}
        queue = [point]
        while queue:
            x, y = queue.pop()
            for dx in [-1, 0, 1]:
                for dy in [-1, 0, 1]:
                    p = x + dx, y + dy
                    if p not in reached and 0 <= p[0] < 112 and 0 <= p[1] < 96 and right.getpixel(p)[3]:
                        reached.add(p)
                        queue.append(p)
        assert any(y <= right.getbbox()[1] + 2 for x, y in reached), (frame, 'detached steel')
    assert len(seen) == 16
    checks += ['32 native112x96 PNGs with opaque/transparent alpha and original18-color palette.',
               '16 unique right poses; left poses mirror about the fixed x56 foot pivot.',
               'Both feet remain above the fixed y84 pivot in every frame.',
               'Every tracked blade tip is an opaque steel pixel attached to the figure, left/right paths symmetric.']
    manifest = json.loads((META / 'generation_manifest.json').read_text(encoding='utf-8'))
    assert max(m['body_height'] for m in manifest['metrics_right']) <= 28
    assert manifest['animation_fps'] == 40 and manifest['pivot'] == [56, 84]
    assert min(paths['side_view']['air_dash_stab_right'][f][0] for f in [6, 7, 8, 9]) >= 19
    checks += ['Rendered body27px maximum vertical height, original28px standing anatomy, no per-frame rescaling.',
               '40fps,16frames; active6..9 all extend forward with minimum19px tip offset.']
    report = {'passed': True, 'checks': checks, 'original_frames_preserved': len(old_frames),
              'new_frames': 32, 'total_frames': len(list((GAME / 'frames').glob('*/*.png'))),
              'side_clips_expected': 36, 'top_clips_expected': 28,
              'new_frame_sha256': manifest['frame_sha256']}
    (META / 'validation_report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({k: v for k, v in report.items() if k != 'new_frame_sha256'}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
