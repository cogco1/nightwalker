"""Technical native-grid import of independently generated aerial dash artwork.

The same uniform source-to-native scale applies to every frame. No body parts,
poses, effects, or weapons are drawn or reconstructed here.
"""
from pathlib import Path
from PIL import Image
import hashlib
import json
import math
import re
import shutil

META = Path(__file__).resolve().parent
GAME = META.parents[1]
BASE = GAME.parents[1] / 'original_v10/Current_Game'
SOURCE = Path(r'C:\Users\31459\.codex\generated_images\01a13f30-752d-7b42-8e9d-15319dd2e6c9\exec-058018c0-7e7a-4239-a7fc-ea97c0e25513.png')
EDIT_SOURCE = SOURCE.parent / 'exec-6a8a5e8b-dcfc-4833-a889-212d3e0ebb91.png'
PIVOT = (56, 84)
SCALE = 0.18
SOURCE_ANCHOR = (180, 277)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    source_path = META / 'air_dash_stab_source.png'
    if not source_path.exists():
        shutil.copy2(SOURCE, source_path)
    source = Image.open(source_path).convert('RGBA')
    edited_path = META / 'air_dash_stab_frame9_edit_source.png'
    if not edited_path.exists():
        shutil.copy2(EDIT_SOURCE, edited_path)
    edited = Image.open(edited_path).convert('RGBA')
    assert abs(source.width / source.height - 7 / 6) < .005, source.size
    cell = (source.width / 4, source.height / 4)
    source_ratio = (source.width / 1344, source.height / 1152)
    colors = json.loads((GAME / 'art_metadata/master_registration.json').read_text(encoding='utf-8'))['palette']
    palette = [tuple(bytes.fromhex(value)) for value in colors]
    mapping = {}
    frames = []
    tips = []
    metrics = []
    for index in range(16):
        frame_source = edited if index == 9 else source
        cell = (frame_source.width / 4, frame_source.height / 4)
        source_ratio = (frame_source.width / 1344, frame_source.height / 1152)
        image = Image.new('RGBA', (112, 96))
        origin = ((index % 4) * cell[0], (index // 4) * cell[1])
        for y in range(96):
            for x in range(112):
                sx = (SOURCE_ANCHOR[0] + (x - PIVOT[0]) / SCALE) * source_ratio[0]
                sy = (SOURCE_ANCHOR[1] + (y - PIVOT[1]) / SCALE) * source_ratio[1]
                if not (0 <= sx < cell[0] and 0 <= sy < cell[1]):
                    continue
                point = (math.floor(origin[0] + sx + .5), math.floor(origin[1] + sy + .5))
                if point[0] >= frame_source.width or point[1] >= frame_source.height:
                    continue
                color = frame_source.getpixel(point)
                if color[3] < 153:
                    continue
                rgb = color[:3]
                if rgb not in mapping:
                    mapping[rgb] = min(palette, key=lambda candidate: sum((rgb[c] - candidate[c]) ** 2 for c in range(3)))
                image.putpixel((x, y), mapping[rgb] + (255,))
        frames.append(image)
        steel = [(x, y) for y in range(96) for x in range(112)
                 if image.getpixel((x, y)) in [palette[i] + (255,) for i in [14, 15, 16]]]
        assert steel, f'No visible steel in frame {index}'
        # This is a forward thrust/guard sequence; the steel point furthest to
        # the right is the visible sword tip rather than a detached VFX pixel.
        tip = max(steel, key=lambda point: (point[0], point[1]))
        tips.append([tip[0] - PIVOT[0], tip[1] - PIVOT[1]])
        body = [(x, y) for y in range(96) for x in range(112)
                if image.getpixel((x, y))[3] and image.getpixel((x, y))[:3] not in palette[13:17]]
        bbox = [min(x for x, y in body), min(y for x, y in body), max(x for x, y in body) + 1, max(y for x, y in body) + 1]
        metrics.append({'frame': index, 'opaque_bbox': list(image.getbbox()), 'body_bbox_without_steel': bbox,
                        'body_height': bbox[3] - bbox[1], 'steel_tip_native': list(tip), 'steel_tip_relative': tips[-1],
                        'opaque_colors': len(set(pixel for pixel in image.getdata() if pixel[3]))})

    resources = []
    animations = []
    new_paths = {}
    output_hashes = {}
    for direction in ['right', 'left']:
        animation = 'air_dash_stab_' + direction
        directory = GAME / ('frames/side_view_' + direction + '_air_dash_stab')
        directory.mkdir(parents=True, exist_ok=True)
        refs = []
        for index, image in enumerate(frames):
            result = image
            if direction == 'left':
                flipped = image.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
                result = Image.new('RGBA', (112, 96))
                result.paste(flipped.crop((0, 0, 111, 96)), (1, 0))
            path = directory / f'{index:02d}.png'
            result.save(path)
            relative = path.relative_to(GAME).as_posix()
            output_hashes[relative] = sha(path)
            resource_id = f'v14_air_dash_stab_{direction}_{index}'
            resources.append(f'[ext_resource type="Texture2D" path="res://{relative}" id="{resource_id}"]')
            refs.append('{"duration":1.0,"texture":ExtResource("' + resource_id + '")}')
        new_paths[animation] = tips if direction == 'right' else [[-x, y] for x, y in tips]
        animations.append('{"frames":[' + ', '.join(refs) + '],"loop":false,"name":&"' + animation + '","speed":40.0}')

    original = (BASE / 'assets/side_view.tres').read_bytes()
    result = original.replace(b'load_steps=545', b'load_steps=577', 1)
    result = result.replace(b'[resource]', ('\n'.join(resources) + '\n\n[resource]').encode('utf-8'), 1)
    end = result.rfind(b']')
    result = result[:end] + (',\n' + ',\n'.join(animations) + '\n]').encode('utf-8') + result[end + 1:]
    (GAME / 'assets/side_view.tres').write_bytes(result)
    old_paths_raw = (BASE / 'assets/blade_paths.json').read_bytes()
    marker = b'"side_view": {'
    assert old_paths_raw.count(marker) == 1
    additions = ',\n'.join('\t\t' + json.dumps(key) + ': ' + json.dumps(value, separators=(',', ':')) for key, value in new_paths.items())
    new_paths_raw = old_paths_raw.replace(marker, marker + ('\n' + additions + ',').encode('utf-8'), 1)
    (GAME / 'assets/blade_paths.json').write_bytes(new_paths_raw)
    # Assert old JSON values remain byte-independent identical.
    old_values = json.loads(old_paths_raw)
    new_values = json.loads(new_paths_raw)
    for category, entries in old_values.items():
        assert all(new_values[category][name] == value for name, value in entries.items())

    preview = Image.new('RGBA', (448, 384), (13, 17, 24, 255))
    for index, im in enumerate(frames):
        preview.alpha_composite(im, ((index % 4) * 112, (index // 4) * 96))
    preview.resize((1792, 1536), Image.Resampling.NEAREST).save(META / 'air_dash_stab_native_preview_4x.png')
    zoom = frames[7].getbbox()
    frames[7].crop(zoom).resize(((zoom[2] - zoom[0]) * 12, (zoom[3] - zoom[1]) * 12), Image.Resampling.NEAREST).save(META / 'air_dash_stab_peak_12x.png')
    anim = []
    for im in frames:
        pic = Image.new('RGBA', im.size, (13, 17, 24, 255))
        pic.alpha_composite(im)
        anim.append(pic.resize((560, 480), Image.Resampling.NEAREST).convert('RGB'))
    anim[0].save(META / 'air_dash_stab_preview.gif', save_all=True, append_images=anim[1:], duration=65, loop=0, disposal=2)
    report = {'animation': 'air_dash_stab', 'mode': 'built-in image_gen', 'prompt_file': 'prompt.txt',
              'source_file': 'air_dash_stab_source.png', 'source_original': str(SOURCE), 'source_sha256': sha(source_path),
              'targeted_frame9_edit': {'source_file': edited_path.name, 'source_original': str(EDIT_SOURCE),
                   'sha256': sha(edited_path), 'prompt_file': 'frame9_edit_prompt.txt',
                   'used_cells': [9], 'other_15_frames': 'Only original source cells used; edited sheet changes outside cell9 discarded.'},
              'references': ['air_idle_registered_reference.png', 'hero_air_identity_reference.png', 'motion_scale_reference.png'],
              'source_size': list(source.size), 'source_grid': [4, 4], 'source_cell': list(cell),
              'frames_per_direction': 16, 'directions': ['right', 'left'], 'native_frame': [112, 96], 'pivot': list(PIVOT),
              'uniform_sampling_scale_all_frames': SCALE, 'source_anchor_all_frames': list(SOURCE_ANCHOR),
              'registration': 'one uniform sampling transform for all 16 frames; no per-frame body resize or posture edit',
              'mirroring': 'left = horizontal flip plus 1 pixel right; x_left=112-x_right, preserving pivot56',
              'blade_detection': 'rightmost on-sprite steel palette indices14/15/16; relative to foot(56,84)',
              'animation_fps': 40, 'loop': False, 'active_frames': [6, 7, 8, 9], 'palette': colors,
              'metrics_right': metrics, 'paths': new_paths, 'frame_sha256': output_hashes,
              'preservation': {'original_frames': 992, 'existing_blade_paths_unchanged': True,
                 'old_resource_definitions': 'byte-preserved; only header load_steps changed and new resources/animation blocks inserted'},
              'body_rendering': {'runtime_scale': [1, 1], 'texture_filter': 'nearest', 'runtime_offset': [-56, -84],
                  'fx': 'Existing runtime lightblade/wind effects remain separate; no detached bright particles baked into sprite.'}}
    (META / 'generation_manifest.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'new_frames': 32, 'metrics': metrics, 'paths': new_paths}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
