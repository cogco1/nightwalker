"""Rebuild only locomotion weapons from a generated cutout and the preserved v07 body layers.

Run from any directory. Input/output paths resolve relative to the repository, not the old artist's machine.
The body/feet, animation ordering, pixel scale, hit timing and all attack sprites are preserved.
"""
from __future__ import annotations
import hashlib
import json
import math
from pathlib import Path
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / 'game'
ART = GAME / 'art_metadata/locomotion_blade_20261017'
ORIGINAL = GAME / 'art_metadata/side_longblade_v07'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pixels(image):
    return list(image.get_flattened_data())


def root_mirror(image):
    result = Image.new(image.mode, image.size)
    result.paste(ImageOps.mirror(image), (1, 0))
    return result


def replace_side_paths(text, name, value):
    start = text.index('"' + name + '":', text.index('"side_view"'))
    start = text.index('[', start)
    depth = 0
    for end in range(start, len(text)):
        depth += (text[end] == '[') - (text[end] == ']')
        if depth == 0:
            replacement = json.dumps(value, indent='\t').replace('\n', '\n\t\t')
            return text[:start] + replacement + text[end+1:]
    raise ValueError(name)


def main():
    original_report = json.loads((ORIGINAL / 'export_report.json').read_text(encoding='utf-8'))
    palette = [tuple(bytes.fromhex(value)) for value in original_report['palette']]
    weapon_palette = [palette[i] for i in [0, 1, 2, 13, 14, 15, 16]]
    steel_colors = {palette[i] for i in [14, 15, 16]}
    source = Image.open(ART / 'generated_carry_blade.png').convert('RGBA')
    alpha = source.getchannel('A').point(lambda a: 255 if a >= 128 else 0)
    source.putalpha(alpha)
    native = source.crop(alpha.getbbox()).resize((24, 7), Image.Resampling.NEAREST)
    for y in range(native.height):
        for x in range(native.width):
            pixel = native.getpixel((x, y))
            if pixel[3] >= 128:
                color = min(weapon_palette, key=lambda c: sum((a-b)**2 for a,b in zip(c,pixel[:3])))
                native.putpixel((x,y), (*color,255))
            else:
                native.putpixel((x,y), (0,0,0,0))
    native.save(ART / 'carry_blade_native.png')
    path_file = GAME / 'assets/blade_paths.json'
    path_text = path_file.read_text(encoding='utf-8')
    path_data = json.loads(path_text)
    original_paths = json.loads(path_text)
    records = []
    for action in ['walk', 'run']:
        clip = f'side_view_right_{action}'
        base_atlas = Image.open(ORIGINAL / 'edit_references' / f'{clip}.png').convert('RGBA').resize((448,384),Image.Resampling.NEAREST)
        # Front carry for walking; trailing carry for running. Both retain the existing gloved wrist motion.
        blade = native if action == 'walk' else ImageOps.mirror(native)
        grip = (2,1) if action == 'walk' else (21,1)
        tips = {'right': [], 'left': []}
        for index in range(16):
            record = original_report['clips'][clip]['body_preservation']['frames'][index]
            base = base_atlas.crop((index%4*112,index//4*96,index%4*112+112,index//4*96+96))
            old_mask = Image.open(ORIGINAL / 'weapon_masks' / clip / f'{index:02}_old.png').convert('L')
            body = base.copy()
            for y in range(96):
                for x in range(112):
                    if old_mask.getpixel((x,y)):
                        body.putpixel((x,y),(0,0,0,0))
            wrist = tuple(round(value) for value in record['old_wrist'])
            weapon = Image.new('RGBA',(112,96))
            weapon.paste(blade,(wrist[0]-grip[0],wrist[1]-grip[1]))
            # Coat, gloves, boots and all other original body pixels occlude the sword naturally.
            result = Image.alpha_composite(weapon,body)
            for direction in ['right','left']:
                name = f'side_view_{direction}_{action}'
                frame = result if direction == 'right' else root_mirror(result)
                protected = body if direction == 'right' else root_mirror(body)
                old_path = GAME / 'frames' / name / f'{index:02}.png'
                # Existing artwork outside the former weapon area must remain byte-identical as RGBA pixels.
                changes = sum(a != b and b[3] != 0 for a,b in zip(pixels(frame),pixels(protected)))
                if changes:
                    raise ValueError(f'{name}/{index}: {changes} protected pixels changed')
                points = [(x,y) for y in range(96) for x in range(112)
                          if frame.getpixel((x,y))[3] and frame.getpixel((x,y))[:3] in steel_colors]
                actual_wrist = wrist if direction == 'right' else (112-wrist[0],wrist[1])
                tip = max(points,key=lambda p:math.dist(p,actual_wrist))
                local_tip = [tip[0]-56,tip[1]-84]
                expected_sign = (1 if direction == 'right' else -1) * (1 if action == 'walk' else -1)
                if local_tip[0] * expected_sign <= 0 or tip[1] >= 84:
                    raise ValueError(f'{name}/{index}: inconsistent carry direction/ground clearance')
                mask = Image.new('L',(112,96))
                for y in range(96):
                    for x in range(112):
                        if protected.getpixel((x,y))[3]:
                            mask.putpixel((x,y),255)
                mask_dir=ART / 'body_masks' / name
                mask_dir.mkdir(parents=True,exist_ok=True)
                mask.save(mask_dir / f'{index:02}.png')
                frame.save(old_path)
                tips[direction].append(local_tip)
                records.append({'clip':name,'frame':index,'wrist':list(actual_wrist),'tip_local':local_tip,
                                'protected_body_pixels':sum(p[3]!=0 for p in pixels(protected)),
                                'protected_body_changes':changes,'pixel_sha256':hashlib.sha256(frame.tobytes()).hexdigest()})
        for direction in ['right','left']:
            key=f'{action}_{direction}'
            path_text=replace_side_paths(path_text,key,tips[direction])
            path_data['side_view'][key]=tips[direction]
    if json.loads(path_text) != path_data:
        raise ValueError('Unexpected blade path changes')
    path_file.write_text(path_text,encoding='utf-8',newline='\n')
    changed_keys=[key for key in path_data['side_view'] if path_data['side_view'][key]!=original_paths['side_view'][key]]
    report={'date':'2026-10-17','source_commit':'a6ccf514ecfeb8503c7cfc354cb594e8742f25c0',
            'generator':'built-in image_gen; native quantization and protected-body compositing',
            'generated_source_sha256':sha(ART/'generated_carry_blade.png'),
            'native_canvas':[112,96],'pivot':[56,84],'frames':records,'changed_path_keys':changed_keys,
            'policy':{'walk':'blade stays in front of the facing','run':'blade trails behind the facing'},
            'protected_body_changes':sum(r['protected_body_changes'] for r in records),
            'original_art_sources':'../side_longblade_v07/edit_references and weapon_masks',
            'runtime_code_changes':False}
    (ART/'import_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'frames_rebuilt':len(records),'protected_body_changes':report['protected_body_changes'],
                      'changed_path_keys':changed_keys},ensure_ascii=False))


if __name__=='__main__':
    main()
