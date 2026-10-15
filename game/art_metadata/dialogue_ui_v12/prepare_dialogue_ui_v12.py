"""Register generated portrait and official font sources without painting new artwork."""
import hashlib
import json
import shutil
import zipfile
from pathlib import Path
from PIL import Image

BASE = Path(__file__).resolve().parent
GAME = BASE / 'game_v11'
SOURCE = Path('C:/Users/31459/.codex/generated_images/01a13585-e7c6-7633-9b84-d80f33782b30/exec-03626952-ae56-4024-a2c5-c848ab4b2862.png')
ART = BASE / 'art/characters/dialogue_portrait_v12'
META = GAME / 'art_metadata/dialogue_ui_v12'
FONTS = GAME / 'assets/fonts'
UI = GAME / 'assets/ui'
for folder in [ART, META, UI]:
    folder.mkdir(parents=True, exist_ok=True)
shutil.copy2(SOURCE, ART / 'hero_portrait_source.png')
shutil.copy2(BASE / 'hero_dialogue_reference.png', ART / 'approved_sprite_reference.png')
im = Image.open(SOURCE).convert('RGBA')
print('Generated portrait:', im.size, 'bounds:', im.getbbox())
# Technical crop, nearest-neighbor reduction, binary alpha, and palette registration.
cropped = im.crop(im.getbbox())
cropped.thumbnail((46, 62), Image.Resampling.NEAREST)
native = Image.new('RGBA', (48, 64))
native.alpha_composite(cropped, ((48 - cropped.width) // 2, 64 - cropped.height))
alpha = native.getchannel('A').point(lambda value: 255 if value >= 128 else 0)
native = native.convert('RGB').quantize(colors=20, method=Image.Quantize.MEDIANCUT).convert('RGBA')
native.putalpha(alpha)
native.save(UI / 'hero_portrait.png')
native.resize((384, 512), Image.Resampling.NEAREST).save(META / 'hero_portrait_preview.png')
with zipfile.ZipFile(BASE / 'art/fonts/fusion-pixel-font-10px-proportional-2026.09.25.zip') as archive:
    for name in archive.namelist():
        if name.lower().endswith('.txt'):
            target = FONTS / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(archive.read(name))
font = FONTS / 'fusion-pixel-10px-proportional-zh_hans.otf'
font_metadata = dict(name='Fusion Pixel Font', version='2026.09.25', native_size=10,
    source='https://github.com/TakWolf/fusion-pixel-font',
    release='https://github.com/TakWolf/fusion-pixel-font/releases/tag/2026.09.25',
    asset='https://github.com/TakWolf/fusion-pixel-font/releases/download/2026.09.25/fusion-pixel-font-10px-proportional-otf-v2026.09.25.zip',
    license='SIL Open Font License 1.1', sha256=hashlib.sha256(font.read_bytes()).hexdigest(),
    godot_settings_source='https://github.com/TakWolf/godot-pixel-font-localization-sample')
(FONTS / 'source.json').write_text(json.dumps(font_metadata, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
shutil.copy2(ART / 'hero_portrait_source.png', META / 'hero_portrait_source.png')
shutil.copy2(ART / 'approved_sprite_reference.png', META / 'approved_sprite_reference.png')
shutil.copy2(Path(__file__), META / Path(__file__).name)
print('Native portrait:', native.size, 'colors:', len(native.getcolors(4096)), 'font:', font.stat().st_size)
