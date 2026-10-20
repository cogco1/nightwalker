"""Normalize imagegen enemy concepts to a common native sprite grid.

Artwork stays in source_art. This tool only separates the three concepts,
uses nearest sampling, removes faint alpha fringes and matches a shared palette.
"""
from pathlib import Path
import hashlib
import json
import shutil

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'outputs/enemy_concepts_v01'
PALETTE = [(14, 17, 21), (24, 28, 33), (36, 42, 48), (50, 59, 65),
           (69, 78, 80), (98, 106, 107), (143, 151, 151), (42, 41, 32),
           (63, 61, 43), (86, 82, 58), (113, 104, 77), (106, 54, 30),
           (174, 72, 18), (223, 145, 41), (255, 201, 83), (50, 168, 203)]
BG = (21, 25, 30)


def cleaned(image):
    pixels = np.array(image.convert('RGBA'))
    visible = pixels[:, :, 3] >= 128
    pixels[:, :, 3] = np.where(visible, 255, 0)
    pixels[~visible] = 0
    return Image.fromarray(pixels)


def groups_of_columns(mask):
    columns = np.flatnonzero(mask.sum(axis=0) > 2)
    groups = []
    for column in columns:
        if not groups or column > groups[-1][-1] + 10:
            groups.append([int(column)])
        else:
            groups[-1].append(int(column))
    if len(groups) != 3:
        raise ValueError('Expected three isolated silhouettes, got ' + str(len(groups)))
    return groups


def main():
    for folder in ['source_art', 'asset_images', 'preview_images']:
        (OUT / folder).mkdir(parents=True, exist_ok=True)
    records = json.loads((OUT / 'generation_prompts.json').read_text(encoding='utf-8'))
    designs = json.loads((OUT / 'enemy_designs.json').read_text(encoding='utf-8'))
    palette = Image.new('P', (1, 1))
    palette.putpalette(np.tile(np.array(PALETTE), (16, 1)).ravel().tolist())
    info = {'mode': 'built-in imagegen', 'native_cell': [64, 64],
            'human_height_px': 32, 'drone_width_px': 28, 'alpha_values': [0, 255],
            'native_palette': PALETTE, 'sampling': 'nearest', 'animation_frames': False,
            'classes': {}, 'runtime_changes': False}
    font = ImageFont.truetype('C:/Windows/Fonts/simhei.ttf', 26)
    small_font = ImageFont.truetype('C:/Windows/Fonts/simhei.ttf', 18)
    overview = Image.new('RGB', (1536, 7 * 300 + 100), BG)
    draw = ImageDraw.Draw(overview)
    draw.text((30, 24), '夜行者 / 外骨骼守卫体系 / 概念 v0.1', font=font, fill=(236, 224, 197))
    draw.text((32, 64), '每类三个造型提案，非动画帧  |  人形32原生像素高  |  原生像素最近邻放大',
              font=small_font, fill=(154, 166, 168))
    for row, key in enumerate(designs['order']):
        entry = next(item for item in records['assets'] if item['key'] == key)
        source = OUT / 'source_art' / (key + '.png')
        if not source.exists():
            shutil.copy2(entry['path'], source)
        image = cleaned(Image.open(source))
        mask = np.array(image.getchannel('A')) > 0
        groups = groups_of_columns(mask)
        split = [0] + [round((groups[i][-1] + groups[i + 1][0]) / 2) for i in range(2)] + [image.width]
        sheet = Image.new('RGBA', (192, 64))
        variants = []
        for index in range(3):
            cell = image.crop((split[index], 0, split[index + 1], image.height))
            bounds = cell.getchannel('A').getbbox()
            if not bounds:
                raise ValueError('Empty variant: ' + key)
            art = cell.crop(bounds)
            scale = 28 / art.width if key == 'laser_drone' else 32 / art.height
            size = (max(1, round(art.width * scale)), max(1, round(art.height * scale)))
            if size[0] > 56 or size[1] > 48:
                raise ValueError('Concept is too large for native cell: ' + key + str(size))
            native = cleaned(art.resize(size, Image.Resampling.NEAREST))
            rgb = native.convert('RGB').quantize(palette=palette, dither=Image.Dither.NONE).convert('RGB')
            native = Image.merge('RGBA', (*rgb.split(), native.getchannel('A')))
            result = np.array(native)
            result[result[:, :, 3] == 0] = 0
            native = Image.fromarray(result)
            sprite = Image.new('RGBA', (64, 64))
            bottom = 46 if key == 'laser_drone' else 56
            position = ((64 - size[0]) // 2, bottom - size[1] + 1)
            sprite.paste(native, position)
            sprite.save(OUT / 'asset_images' / (key + '_' + 'ABC'[index] + '.png'), optimize=True)
            sheet.paste(sprite, (index * 64, 0))
            variants.append({'variant': 'ABC'[index], 'source_rect': [split[index] + bounds[0], bounds[1],
                             bounds[2] - bounds[0], bounds[3] - bounds[1]],
                             'sample_size': list(size), 'native_used_rect': list(sprite.getchannel('A').getbbox()),
                             'foot_y': 56 if key != 'laser_drone' else None})
        sheet_path = OUT / 'asset_images' / (key + '_native.png')
        sheet.save(sheet_path, optimize=True)
        preview = Image.new('RGBA', sheet.size, BG + (255,))
        preview.alpha_composite(sheet)
        preview.convert('RGB').resize((1536, 512), Image.Resampling.NEAREST).save(
            OUT / 'preview_images' / (key + '_preview.png'))
        line = sheet.resize((1152, 384), Image.Resampling.NEAREST)
        # Crop only transparent top/bottom margin for the compact summary plate.
        line = line.crop((0, 96, 1152, 384))
        overview.paste(line, (360, 100 + row * 300), line)
        d = designs['classes'][key]
        draw.text((32, 126 + row * 300), d['code'], font=font, fill=(223, 145, 41))
        draw.text((32, 168 + row * 300), d['callsign'], font=font, fill=(236, 224, 197))
        draw.text((32, 210 + row * 300), d['name'], font=small_font, fill=(154, 166, 168))
        info['classes'][key] = {'source': str(source.relative_to(ROOT)), 'source_size': list(image.size),
                                'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                                'sheet': str(sheet_path.relative_to(ROOT)), 'variants': variants}
    overview.save(OUT / 'overview.png')
    (OUT / 'asset_info.json').write_text(json.dumps(info, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'classes': len(info['classes']), 'variants': 21, 'native_palette': len(PALETTE),
                      'human_height': 32, 'runtime_changes': False}))


if __name__ == '__main__':
    main()
