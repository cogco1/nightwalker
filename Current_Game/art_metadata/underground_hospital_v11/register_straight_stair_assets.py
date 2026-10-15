"""Re-export the selected image edit with nearest pixels and the approved palette."""
from pathlib import Path
import hashlib
import json
from PIL import Image

HERE=Path(__file__).resolve().parent
GAME=next((p for p in HERE.parents if (p/'project.godot').is_file()),HERE.parents[2]/'game_v11')


def main():
    record_path=HERE/'straight_stair_revision_manifest.json'
    record=json.loads(record_path.read_text(encoding='utf-8'))
    colors=json.loads((HERE/'stair_door_removal_manifest.json').read_text(encoding='utf-8'))['palette_rgb']
    palette=Image.new('P',(1,1))
    palette.putpalette([channel for rgb in colors for channel in rgb]+colors[-1]*(256-len(colors)))
    native=Image.open(HERE/record['selected_source']).convert('RGB').resize((640,360),Image.Resampling.NEAREST)
    native=native.quantize(palette=palette,dither=Image.Dither.NONE).convert('RGB')
    native.save(HERE/record['native_asset'])
    native.save(GAME/'assets/underground_hospital'/record['native_asset'])
    native.resize((1280,720),Image.Resampling.NEAREST).save(HERE/'hospital_side_overview_2x_v11.png')
    record['native_sha256']=hashlib.sha256((HERE/record['native_asset']).read_bytes()).hexdigest()
    record_path.write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('Registered straight stair:640x360,fixed39-colorpalette,nearestpixels.')


if __name__=='__main__':
    main()
