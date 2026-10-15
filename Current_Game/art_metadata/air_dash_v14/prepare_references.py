from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent
GAME = ROOT.parents[1]

ROOT.mkdir(parents=True, exist_ok=True)
atlas = Image.new('RGBA', (448, 384))
for i in range(16):
    source = Image.open(GAME / 'frames/side_view_right_air_idle' / f'{i:02d}.png').convert('RGBA')
    atlas.alpha_composite(source, ((i % 4) * 112 + 16, (i // 4) * 96 + 16))
atlas.resize((1792, 1536), Image.Resampling.NEAREST).save(ROOT / 'air_idle_registered_reference.png')

im = Image.open(GAME / 'frames/side_view_right_air_idle/07.png')
bounds = im.getbbox()
im.crop(bounds).resize(((bounds[2] - bounds[0]) * 12, (bounds[3] - bounds[1]) * 12), Image.Resampling.NEAREST).save(ROOT / 'hero_air_identity_reference.png')

atlas = Image.new('RGBA', (224, 96))
atlas.alpha_composite(Image.open(GAME / 'frames/side_view_right_dash_stab/07.png'), (0, 0))
atlas.alpha_composite(Image.open(GAME / 'frames/side_view_right_air_attack3/07.png'), (112 + 16, 16))
atlas.resize((1120, 480), Image.Resampling.NEAREST).save(ROOT / 'motion_scale_reference.png')
print(ROOT)
