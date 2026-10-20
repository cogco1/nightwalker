"""Normalize generated enemy animation poses without redrawing their articulation.

Each unit uses one pixel scale, calibrated from its eight standing walk poses.
The same scale is kept for recoil, melee arcs and prone poses.  Artwork is only
nearest-sampled, aligned on integer foot planes and palette-matched offline.
"""
from pathlib import Path
import hashlib
import json
import shutil

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'outputs/enemy_animations_v01'
RUNTIME = ROOT / 'game/assets/enemy_animations_v01'
CELL = (96, 64)
ANCHOR = (48, 57)
FPS = {'hover': 10, 'laser': 12, 'walk': 12, 'fire': 14, 'attack': 14,
       'prone_down': 12, 'prone_crawl': 8, 'prone_fire': 12}


def clean(image):
    pixels = np.array(image.convert('RGBA'))
    mask = pixels[:, :, 3] >= 128
    pixels[:, :, 3] = np.where(mask, 255, 0)
    pixels[~mask] = 0
    return Image.fromarray(pixels)


def source_cells(record):
    source = OUT / 'source_art' / (record['key'] + '_' + record['batch'] + '.png')
    source.parent.mkdir(exist_ok=True)
    if not source.exists():
        shutil.copy2(record['path'], source)
    image = clean(Image.open(source))
    if image.width % 4 or image.height % 4:
        raise ValueError('Source must have exactly four equal columns and rows: ' + source.name)
    width = image.width // 4
    # The generated drawings form four rows, but their feet can exceed a
    # mathematical quarter boundary. Split at the real transparent gutters.
    mask = np.array(image.getchannel('A')) > 0
    rows = np.flatnonzero(mask.sum(axis=1) > 6)
    bands = []
    for row in rows:
        if not bands or row > bands[-1][-1] + 3:
            bands.append([int(row)])
        else:
            bands[-1].append(int(row))
    if len(bands) != 4:
        raise ValueError('Expected four separated pose rows: ' + source.name + str([(b[0], b[-1]) for b in bands]))
    boundaries = [0] + [round((bands[i][-1] + bands[i + 1][0]) / 2) for i in range(3)] + [image.height]
    rects = []
    offsets = []
    for y in range(4):
        occupied = mask[boundaries[y]:boundaries[y + 1]].any(axis=0)
        columns = [0]
        for divider in range(1, 4):
            nominal = divider * width
            left, right = nominal - width // 4, nominal + width // 4
            empty = np.flatnonzero(~occupied[left:right]) + left
            gaps = []
            for x in empty:
                if not gaps or x > gaps[-1][-1] + 1:
                    gaps.append([int(x)])
                else:
                    gaps[-1].append(int(x))
            if not gaps:
                raise ValueError('Missing transparent column gutter: ' + source.name)
            gap = max(gaps, key=len)
            columns.append(round((gap[0] + gap[-1]) / 2))
        columns.append(image.width)
        for x in range(4):
            rects.append((columns[x], boundaries[y], columns[x + 1], boundaries[y + 1]))
            offsets.append(columns[x] - x * width)
    cells = [image.crop(rect) for rect in rects]
    record['_source_rects'] = rects
    record['_source_x_offsets'] = offsets
    return source, cells


def foot_x(image):
    array = np.array(image.getchannel('A'))
    box = image.getchannel('A').getbbox()
    rows = array[max(box[1], box[3] - 10):box[3]]
    _, xs = np.where(rows > 0)
    return (float(xs.min()) + float(xs.max())) / 2


def main():
    selection = json.loads((OUT / 'selection.json').read_text(encoding='utf-8'))
    records = json.loads((OUT / 'generation_prompts.json').read_text(encoding='utf-8'))['assets']
    if len(records) != 9:
        raise ValueError('Require all nine final two-action source sheets')
    palette_colors = selection['palette'] + [[241, 245, 240], [103, 222, 244]]
    palette = Image.new('P', (1, 1))
    palette.putpalette(np.tile(np.array(palette_colors), (15, 1))[:256].ravel().tolist())
    manifest = {'version': 1, 'date': '2026-10-21', 'cell_size': list(CELL),
                'foot_anchor': list(ANCHOR), 'native_body_height': 32, 'native_drone_width': 28,
                'palette': palette_colors, 'scale': 1, 'texture_filter': 'nearest',
                'draw_direction': 'right', 'left_direction': 'flip_h', 'units': []}
    info = {'source_tool': 'built-in imagegen', 'per_frame_resize': False,
            'source_partition': 'transparent row/column gutters; preserve each nominal horizontal origin',
            'ground_alignment': 'integer sole plane; fixed horizontal unit anchor', 'units': {}}
    for unit in selection['units']:
        unit_id = unit['unit']
        jobs = [record for record in records if record['key'] == unit_id]
        loaded = [(record, *source_cells(record)) for record in jobs]
        calibration_record, _, calibration_cells = next(item for item in loaded if item[0]['a'] in ['walk', 'hover'])
        calibration = calibration_cells[:8]
        calibration_offsets = calibration_record['_source_x_offsets'][:8]
        boxes = [cell.getchannel('A').getbbox() for cell in calibration]
        if unit['class'] == 'laser_drone':
            scale = 28 / float(np.median([box[2] - box[0] for box in boxes]))
            source_x = float(np.median([(box[0] + box[2]) / 2 + offset for box, offset in zip(boxes, calibration_offsets)]))
        else:
            scale = 32 / float(np.median([box[3] - box[1] for box in boxes]))
            source_x = float(np.median([foot_x(cell) + offset for cell, offset in zip(calibration, calibration_offsets)]))
        runtime = RUNTIME / unit_id
        images = OUT / 'asset_images' / unit_id
        runtime.mkdir(parents=True, exist_ok=True)
        images.mkdir(parents=True, exist_ok=True)
        idle = Image.new('RGBA', CELL)
        idle.paste(Image.open(OUT / 'selected' / unit_id / 'idle.png').convert('RGBA'), (16, 0))
        idle.save(runtime / 'idle.png', optimize=True)
        idle.save(images / 'idle.png', optimize=True)
        descriptor = {k: unit[k] for k in ['unit', 'class', 'variant', 'code', 'callsign', 'name']}
        descriptor.update({'idle': 'res://assets/enemy_animations_v01/' + unit_id + '/idle.png', 'actions': []})
        details = {'unit_scale': scale, 'source_root_x': source_x, 'actions': {}}
        for record, source, cells in loaded:
            for group, action in enumerate([record['a'], record['b']]):
                sheet = Image.new('RGBA', (CELL[0] * 4, CELL[1] * 2))
                frames = OUT / 'frames' / unit_id / action
                frames.mkdir(parents=True, exist_ok=True)
                frame_info = []
                for index, original in enumerate(cells[group * 8:(group + 1) * 8]):
                    size = (round(original.width * scale), round(original.height * scale))
                    sampled = clean(original.resize(size, Image.Resampling.NEAREST))
                    rgb = sampled.convert('RGB').quantize(palette=palette, dither=Image.Dither.NONE).convert('RGB')
                    sampled = Image.merge('RGBA', (*rgb.split(), sampled.getchannel('A')))
                    used = sampled.getchannel('A').getbbox()
                    if used is None:
                        raise ValueError('Empty frame: ' + unit_id + '/' + action)
                    bottom = 46 if unit['class'] == 'laser_drone' else 57
                    source_offset = record['_source_x_offsets'][group * 8 + index]
                    translation = (ANCHOR[0] - round(source_x * scale) + round(source_offset * scale), bottom - used[3])
                    canvas = Image.new('RGBA', CELL)
                    canvas.paste(sampled, translation)
                    before = np.count_nonzero(np.array(sampled.getchannel('A')))
                    after = np.count_nonzero(np.array(canvas.getchannel('A')))
                    if before != after:
                        raise ValueError('Clipped frame: ' + unit_id + '/' + action + '/' + str(index))
                    canvas.save(frames / ('%02d.png' % index), optimize=True)
                    sheet.paste(canvas, ((index % 4) * CELL[0], (index // 4) * CELL[1]))
                    frame_info.append({'index': index, 'source_cell': group * 8 + index,
                        'source_rect': list(record['_source_rects'][group * 8 + index]),
                        'nominal_origin_offset_x': source_offset,
                        'translation': list(translation), 'used_rect': list(canvas.getchannel('A').getbbox()),
                        'opaque_pixels': int(after)})
                sheet.save(runtime / (action + '.png'), optimize=True)
                sheet.save(images / (action + '.png'), optimize=True)
                descriptor['actions'].append({'name': action,
                    'sheet': 'res://assets/enemy_animations_v01/' + unit_id + '/' + action + '.png',
                    'frames': 8, 'columns': 4, 'fps': FPS[action],
                    'loop': action in ['walk', 'hover', 'prone_crawl']})
                details['actions'][action] = {'source': str(source.relative_to(ROOT)),
                    'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'frames': frame_info}
        manifest['units'].append(descriptor)
        info['units'][unit_id] = details
    for path in [OUT / 'manifest.json', RUNTIME / 'manifest.json']:
        path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    (OUT / 'asset_info.json').write_text(json.dumps(info, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(json.dumps({'units': len(manifest['units']), 'actions': 18, 'animation_frames': 144,
                      'cell_size': list(CELL), 'foot_anchor': list(ANCHOR)}))


if __name__ == '__main__':
    main()
