"""Register the built-in image edit using the preserved final runtime palette."""
from pathlib import Path
import json
from PIL import Image

HERE = Path(__file__).resolve().parent


def main():
    metadata = json.loads((HERE/'stair_door_removal_manifest.json').read_text(encoding='utf-8'))
    colors = metadata['palette_rgb']
    palette = Image.new('P', (1, 1))
    palette.putpalette([c for rgb in colors for c in rgb] + colors[-1] * (256-len(colors)))
    native = Image.open(HERE/metadata['selected_output']).convert('RGB').resize((640,224),Image.Resampling.NEAREST)
    native = native.quantize(palette=palette,dither=Image.Dither.NONE).convert('RGB')
    native.save(HERE/metadata['native_asset'])
    native.resize((1280,448),Image.Resampling.NEAREST).save(HERE/'hospital_floor_1_preview_2x_v11.png')
    # Works both in the authoring workspace and in the delivered project.
    project = next((p for p in HERE.parents if (p/'project.godot').is_file()), HERE.parents[2]/'game_v11')
    native.save(project/'assets/underground_hospital'/metadata['native_asset'])
    print('Registered stair-side door removal:640x224, fixed palette, nearest pixels.')


if __name__ == '__main__':
    main()
