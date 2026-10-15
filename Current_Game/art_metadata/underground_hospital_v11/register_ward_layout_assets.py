"""Re-export the selected built-in ward edit on the preserved native pixel grid."""
from pathlib import Path
import hashlib
import json
from PIL import Image

HERE=Path(__file__).resolve().parent
GAME=next((p for p in HERE.parents if (p/'project.godot').is_file()),HERE.parents[2]/'game_v11')


def main():
    path=HERE/'ward_layout_revision_manifest.json'
    record=json.loads(path.read_text(encoding='utf-8'))
    colors=json.loads((HERE/'stair_door_removal_manifest.json').read_text(encoding='utf-8'))['palette_rgb']
    palette=Image.new('P',(1,1))
    palette.putpalette([channel for rgb in colors for channel in rgb]+colors[-1]*(256-len(colors)))
    native=Image.open(HERE/record['selected_source']).convert('RGB').resize((640,224),Image.Resampling.NEAREST)
    native=native.quantize(palette=palette,dither=Image.Dither.NONE).convert('RGB')
    native.save(HERE/'hospital_floor_1_native.png')
    native.save(GAME/'assets/underground_hospital/hospital_floor_1_native.png')
    native.resize((1280,448),Image.Resampling.NEAREST).save(HERE/'hospital_floor_1_preview_2x_v11.png')
    record['native_sha256']=hashlib.sha256((HERE/'hospital_floor_1_native.png').read_bytes()).hexdigest()
    path.write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('Registered selected ward layout:640x224,fixed39-colorpalette,nearestpixels.')


if __name__=='__main__':
    main()
