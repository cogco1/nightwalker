"""Register AI-generated security sprites onto the game's native pixel grid.

Only technical crop, nearest-neighbor resize, alpha threshold, and palette
quantization are performed. This script does not redraw any asset.
"""
from pathlib import Path
from PIL import Image
import hashlib
import json
import shutil

META = Path(__file__).resolve().parent
GAME = META.parents[1]
OUT = GAME / 'assets/underground_hospital/security'
SOURCE_ROOT = Path(r'C:\Users\31459\.codex\generated_images\01a13f30-752d-7b42-8e9d-15319dd2e6c9')
SOURCES = {
    'door_source.png': SOURCE_ROOT / 'exec-61dbcea2-7346-46a5-a236-b0d1401b6e54.png',
    'breaker_sheet_source.png': SOURCE_ROOT / 'exec-74408277-702e-4021-bcfb-dbf67b10710d.png',
}
PALETTE = [
    (8, 20, 29), (13, 25, 35), (18, 33, 44), (24, 41, 53),
    (31, 50, 63), (39, 60, 72), (49, 72, 84), (61, 86, 97),
    (75, 106, 118), (88, 131, 141), (107, 155, 162),
    (107, 50, 53), (145, 71, 70), (105, 83, 48),
    (157, 125, 67), (208, 173, 101),
]


def technical_register(im):
    alpha = im.getchannel('A').point(lambda v: 255 if v >= 128 else 0)
    palette_image = Image.new('P', (1, 1))
    palette_image.putpalette(sum((list(c) for c in PALETTE), []) + [0] * (768 - 3 * len(PALETTE)))
    rgb = im.convert('RGB').quantize(palette=palette_image, dither=Image.Dither.NONE).convert('RGB')
    result = rgb.convert('RGBA')
    result.putalpha(alpha)
    # Zero the invisible RGB channels too, for clean transparent PNG exports.
    result = Image.composite(result, Image.new('RGBA', result.size), alpha)
    return result


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, original in SOURCES.items():
        target = META / name
        if not target.exists():
            shutil.copy2(original, target)

    door = Image.open(META / 'door_source.png').convert('RGBA')
    door_crop = (139, 242, 1635, 638)
    door = technical_register(door.crop(door_crop).resize((32, 16), Image.Resampling.NEAREST))
    door.save(OUT / 'door_closed.png')

    sheet = Image.open(META / 'breaker_sheet_source.png').convert('RGBA')
    closed_crop = (80, 141, 628, 870)
    closed = Image.new('RGBA', (24, 30))
    closed.paste(sheet.crop(closed_crop).resize((20, 30), Image.Resampling.NEAREST), (4, 0))
    closed = technical_register(closed)
    closed.save(OUT / 'breaker_closed.png')

    open_crop = (831, 141, 1456, 870)
    opened = Image.new('RGBA', (24, 30))
    opened.paste(sheet.crop(open_crop).resize((25, 30), Image.Resampling.NEAREST), (-1, 0))
    opened = technical_register(opened)
    opened.save(OUT / 'breaker_open.png')

    preview = Image.new('RGBA', (100, 40), (8, 15, 21, 255))
    preview.alpha_composite(door, (3, 12))
    preview.alpha_composite(closed, (42, 4))
    preview.alpha_composite(opened, (73, 4))
    preview.resize((800, 320), Image.Resampling.NEAREST).save(META / 'security_native_preview_8x.png')
    files = []
    for path in sorted(OUT.glob('*.png')):
        im = Image.open(path)
        opaque = [p for p in im.getdata() if p[3]]
        files.append({'file': str(path.relative_to(GAME)).replace('\\', '/'), 'native_size': list(im.size),
                      'sha256': sha(path), 'opaque_colors': len(set(opaque)),
                      'alpha_values': sorted(set(im.getchannel('A').getdata()))})
    manifest = {
        'revision': 'hospital_security_v13',
        'generation_mode': 'built-in image_gen, transparent_background=true',
        'art_use': 'top-down only; closed password door and key-locked breaker cabinet; no NPCs',
        'prompts_file': 'prompts.json',
        'references': [
            'assets/underground_hospital/hospital_floor_1_native.png',
            'assets/underground_hospital/hospital_floor_2_native.png',
            'frames/side_view_right_idle/00.png',
        ],
        'sources': [{'file': name, 'original_path': str(path), 'sha256': sha(META / name)} for name, path in SOURCES.items()],
        'technical_processing': {'resampling': 'nearest neighbor only', 'alpha_threshold': 128,
             'palette_rgb': [list(c) for c in PALETTE], 'dithering': False,
             'door_source_crop': list(door_crop), 'breaker_closed_source_crop': list(closed_crop),
             'breaker_open_source_crop': list(open_crop),
             'cabinet_registration': 'Both 24x30 frames align cabinet bodies at approximately x=4; open cover extends left.'},
        'outputs': files,
        'runtime': {'door_closed': '32x16; split at x=16 into two sliding halves, draw with nearest texture filter',
                    'breaker': '24x30 closed/open frames; nearest filter, integer positions'},
    }
    (META / 'generation_manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(files, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
