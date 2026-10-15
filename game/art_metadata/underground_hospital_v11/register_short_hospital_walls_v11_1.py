"""Save and register the built-in low-wall edits on the approved pixel grid."""
from pathlib import Path
import hashlib
import json
import shutil
from PIL import Image

BASE=Path(__file__).resolve().parent
ART=BASE/'art/environments/underground_hospital_v01'
GAME=BASE/'game_v11'
if not ART.is_dir():
    ART=BASE
if not (GAME/'project.godot').is_file():
    GAME=next(p for p in BASE.parents if (p/'project.godot').is_file())
GENERATED=Path('C:/Users/31459/.codex/generated_images/01a13585-e7c6-7633-9b84-d80f33782b30')
SOURCES={1:'exec-e50e316a-607d-478d-b098-721a1608f6d5.png',2:'exec-1ef3069e-bc31-42b6-84c4-ec2f69deb622.png'}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    metadata=json.loads((ART/'short_wall_revision_manifest.json').read_text(encoding='utf-8'))
    colors=json.loads((ART/'stair_door_removal_manifest.json').read_text(encoding='utf-8'))['palette_rgb']
    palette=Image.new('P',(1,1))
    palette.putpalette([c for rgb in colors for c in rgb]+colors[-1]*(256-len(colors)))
    for floor,generated_name in SOURCES.items():
        for kind in ['source','native']:
            source=ART/f'hospital_floor_{floor}_{kind}.png'
            backup=ART/f'hospital_floor_{floor}_{kind}_before_short_walls.png'
            if not backup.exists():
                shutil.copy2(source,backup)
        if (GENERATED/generated_name).is_file():
            shutil.copy2(GENERATED/generated_name,ART/f'hospital_floor_{floor}_source.png')
        native=Image.open(ART/f'hospital_floor_{floor}_source.png').convert('RGB').resize((640,224),Image.Resampling.NEAREST)
        native=native.quantize(palette=palette,dither=Image.Dither.NONE).convert('RGB')
        native.save(ART/f'hospital_floor_{floor}_native.png')
        native.save(GAME/f'assets/underground_hospital/hospital_floor_{floor}_native.png')
        native.resize((1280,448),Image.Resampling.NEAREST).save(ART/f'hospital_floor_{floor}_preview_2x_v11.png')
    metadata['palette_rgb']=colors
    metadata['runtime_sha256']={f'hospital_floor_{i}_native.png':sha(GAME/f'assets/underground_hospital/hospital_floor_{i}_native.png') for i in [1,2]}
    metadata['collision_review']='Existing wall bases now match the short wall faces. Preserved north44/43,divider82..92/135..145 and six doorway gaps; no loss of usable floor.'
    (ART/'short_wall_revision_manifest.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    path=ART/'generation_manifest.json'
    overall=json.loads(path.read_text(encoding='utf-8'))
    if 'short_wall_revision_manifest.json' not in overall['prompt_manifests']:
        overall['prompt_manifests'].append('short_wall_revision_manifest.json')
    overall['current_revision']='v11.1: short top-down walls and clear horizontal floor; approved original player and physical side stairs retained'
    overall['runtime_sha256'].update(metadata['runtime_sha256'])
    path.write_text(json.dumps(overall,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    metadata_folder=GAME/'art_metadata/underground_hospital_v11'
    if ART.resolve()!=metadata_folder.resolve():
        shutil.copytree(ART,metadata_folder,dirs_exist_ok=True,ignore=shutil.ignore_patterns('__pycache__','hospital_large_native_inspect.png'))
    print(json.dumps({'status':'registered','native':[640,224],'colors':len(colors),'floors':2,'mode':'built-in image_gen'}))


if __name__=='__main__':
    main()
