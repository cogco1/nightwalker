"""Normalize generated wreck smoke/fire artwork to native, separate sprite layers.

Only nearest sampling, color/alpha separation and integer alignment are applied.
The original combined VFX sheets and all prompts remain in the delivery folder.
"""
from pathlib import Path
import hashlib
import importlib.util
import json
import shutil

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'outputs/battlefield_ambient_v10'
RUNTIME = ROOT / 'game/assets/battlefield_ambient'
ANCHOR = (32, 58)
SIZE = 64
DRAW_SIZE = 48
FIRE_COLORS = [(48, 27, 21), (92, 37, 19), (150, 57, 16), (206, 91, 17),
               (238, 143, 33), (255, 196, 71), (255, 221, 126)]


def encode(pixels, mask, palette):
    alpha = Image.fromarray(np.where(mask, 255, 0).astype('uint8'))
    rgb = Image.fromarray(pixels[:, :, :3]).quantize(
        palette=palette, dither=Image.Dither.NONE).convert('RGB')
    result = Image.merge('RGBA', (*rgb.split(), alpha))
    result_array = np.array(result)
    result_array[~mask] = 0
    return Image.fromarray(result_array)


def main():
    (OUT / 'source_art').mkdir(parents=True, exist_ok=True)
    (OUT / 'asset_images').mkdir(exist_ok=True)
    spec = importlib.util.spec_from_file_location('native_assets', ROOT / 'tools/build_battlefield_traversal_assets.py')
    native = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(native)
    smoke_palette, smoke_colors = native.approved_palette()
    fire_palette = Image.new('P', (1, 1))
    fire_palette.putpalette(np.tile(np.array(FIRE_COLORS), (37, 1))[:256].ravel().tolist())
    records = json.loads((OUT / 'generation_prompts.json').read_text(encoding='utf-8'))
    variants, art_info = [], []
    for asset in records['assets']:
        key = asset['key']
        raw_path = OUT / 'source_art' / (key + '_combined_sheet.png')
        if not raw_path.exists():
            shutil.copy2(asset['path'], raw_path)
        raw = Image.open(raw_path).convert('RGBA')
        if raw.width * 2 != raw.height * 3:
            raise ValueError('Expected equal square cells in a 3x2 source sheet')
        cell_size = raw.width // 3
        sheets = {kind: Image.new('RGBA', (192, 128)) for kind in ['smoke', 'fire']}
        frames = []
        for index in range(6):
            x, y = index % 3, index // 3
            cell = raw.crop((x * cell_size, y * cell_size, (x + 1) * cell_size, (y + 1) * cell_size))
            pixels = np.array(cell.resize((DRAW_SIZE, DRAW_SIZE), Image.Resampling.NEAREST))
            opaque = pixels[:, :, 3] >= 128
            r, g, b = [pixels[:, :, c].astype(float) for c in range(3)]
            # Include pale gold cores (nearly equal red/green), while the
            # stronger red/blue separation keeps neutral ash in the smoke layer.
            warm = (r - b > np.maximum(24, r * 0.30)) & (r > g * 1.01)
            fire = opaque & warm
            smoke = opaque & ~warm
            fy, fx = np.where(fire)
            if len(fx) < 8 or np.count_nonzero(smoke) < 30:
                raise ValueError('Incomplete generated smoke/fire frame')
            bottom = int(fy.max())
            bottom_xs = np.flatnonzero(fire[bottom])
            center_x = int(bottom_xs[np.argmin(np.abs(bottom_xs - np.mean(bottom_xs)))])
            translation = (ANCHOR[0] - center_x, ANCHOR[1] - bottom)
            frame_info = {'index': index, 'source_rect': [x * cell_size, y * cell_size, cell_size, cell_size],
                          'translation': list(translation)}
            for kind, mask, palette in [('smoke', smoke, smoke_palette), ('fire', fire, fire_palette)]:
                layer = encode(pixels, mask, palette)
                aligned = Image.new('RGBA', (SIZE, SIZE))
                aligned.paste(layer, translation)
                alpha = np.array(aligned.getchannel('A'))
                if np.count_nonzero(alpha) != np.count_nonzero(mask):
                    raise ValueError('Artwork clipped while aligning: ' + key + kind)
                sheets[kind].paste(aligned, (x * SIZE, y * SIZE))
                frame_info[kind] = {'used_rect': list(aligned.getchannel('A').getbbox()),
                                    'opaque_pixels': int(np.count_nonzero(alpha))}
            frames.append(frame_info)
        variant = {'id': key}
        for kind, sheet in sheets.items():
            name = 'vehicle_' + key + '_' + kind + '.png'
            path = OUT / 'asset_images' / name
            sheet.save(path, optimize=True)
            shutil.copy2(path, RUNTIME / name)
            sheet.resize((768, 512), Image.Resampling.NEAREST).save(OUT / 'asset_images' / (path.stem + '_preview_4x.png'))
            variant[kind] = {'texture': 'res://assets/battlefield_ambient/' + name,
                             'frame_size': [SIZE, SIZE], 'frames': [3, 2], 'anchor': list(ANCHOR)}
        variants.append(variant)
        art_info.append({'id': key, 'source': str(raw_path.relative_to(ROOT)),
                         'source_sha256': hashlib.sha256(raw_path.read_bytes()).hexdigest(),
                         'native_frame_size': [SIZE, SIZE], 'native_sheet_size': [192, 128],
                         'drawing_size': [DRAW_SIZE, DRAW_SIZE], 'anchor': list(ANCHOR), 'frames': frames})
    positions = [('sedan_01', [579, 152]), ('van_01', [1009, 149]), ('truck_01', [1253, 147]),
                 ('sedan_02', [1811, 152]), ('van_02', [3201, 149]), ('truck_02', [3533, 147]),
                 ('sedan_03', [4739, 152])]
    settings = json.loads((ROOT / 'outputs/battlefield_ambient_v09/ambient.json').read_text(encoding='utf-8'))
    settings['version'] = 10
    settings['vehicle_effects'] = {'random_seed': 0, 'variants': variants,
        'emitters': [{'id': name, 'vehicle_id': name, 'position': pos,
                      'smoke_opacity': 0.63, 'fire_opacity': 0.94} for name, pos in positions],
        'smoke_period': [1.7, 2.7], 'fire_period': [0.5, 0.85], 'jitter': [1, 0]}
    encoded = json.dumps(settings, ensure_ascii=False, indent=2) + '\n'
    for path in [OUT / 'ambient.json', RUNTIME / 'ambient.json']:
        path.write_text(encoded, encoding='utf-8', newline='\n')
    baseline = json.loads((ROOT / 'outputs/battlefield_ambient_v09/baseline_assets.json').read_text(encoding='utf-8'))
    baseline['base_commit'] = '9eb407ddeca667d79ce3c02a6d1f6663ae488894'
    for path, digest in baseline['sha256'].items():
        if hashlib.sha256((ROOT / path).read_bytes()).hexdigest() != digest:
            raise ValueError('Protected baseline changed: ' + path)
    (OUT / 'baseline_assets.json').write_text(json.dumps(baseline, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (OUT / 'asset_info.json').write_text(json.dumps({'mode': 'built-in imagegen', 'alpha_values': [0, 255],
        'runtime_scale': 1, 'smoke_palette_colors': smoke_colors, 'fire_palette': FIRE_COLORS,
        'normalization': 'nearest 48px art in 64px canvas, warm/neutral layers separated, fixed integer emitter',
        'variants': art_info}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'variants': len(variants), 'sheets': 6, 'frames': 36, 'anchor': ANCHOR,
                      'vehicle_emitters': len(positions)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
