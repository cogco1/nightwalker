"""Normalize v07 imagegen cutouts and crop the generated ground-material sheet."""
from pathlib import Path
import importlib.util
import json
import hashlib
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'outputs/battlefield_density_v07'
RUNTIME=ROOT/'game/assets/battlefield_traversal'
spec=importlib.util.spec_from_file_location('v06_assets',ROOT/'tools/build_battlefield_traversal_assets.py')
legacy=importlib.util.module_from_spec(spec)
spec.loader.exec_module(legacy)
legacy.SOURCES=OUT/'source_art'

def main():
    palette, count=legacy.approved_palette()
    sources=OUT/'source_art'
    shaft_record=json.loads((OUT/'shaft_generation_record.json').read_text(encoding='utf-8'))
    source=Path(shaft_record['path'])
    destination=sources/'lift_shaft.png'
    if not destination.exists(): destination.write_bytes(source.read_bytes())
    with Image.open(sources/'ground_materials.png') as sheet:
        array=np.array(sheet.convert('RGBA'))
    dense=(array[:,:,3]>=128).sum(axis=1)>array.shape[1]*.2
    runs=[]
    for index in np.flatnonzero(dense):
        if not runs or index>runs[-1][-1]+1: runs.append([int(index)])
        else: runs[-1].append(int(index))
    runs=[r for r in runs if len(r)>20]
    if len(runs)!=3: raise ValueError(f'Expected three material strips, found {len(runs)}')
    crops={}
    for name,rows in zip(['ground_concrete','ground_grating','ground_covers'],runs):
        crop=(0,rows[0],array.shape[1],rows[-1]+1)
        Image.fromarray(array).crop(crop).save(sources/(name+'.png'))
        crops[name]=list(crop)
    assets={'megafactory':(1024,320),'industrial_lift':(64,64),'lift_shaft':(96,320),
            'ground_concrete':(512,64),'ground_grating':(512,64),'ground_covers':(512,64)}
    for name,size in [('warehouse',(256,192)),('refinery',(256,256))]:
        if (sources/(name+'.png')).exists(): assets[name]=size
    info={'version':7,'palette_reference':str(legacy.PALETTE_REFERENCE.relative_to(ROOT)),
          'palette_colors':count,'material_sheet_crops':crops,'assets':{}}
    (OUT/'asset_images').mkdir(parents=True,exist_ok=True)
    for name,size in assets.items():
        image,record=legacy.prepare_asset(name,size,palette)
        path=OUT/'asset_images'/(name+'.png')
        image.save(path,optimize=True)
        (RUNTIME/path.name).write_bytes(path.read_bytes())
        image.resize((image.width*2,image.height*2),Image.Resampling.NEAREST).save(OUT/'asset_images'/(name+'_preview_2x.png'))
        record['native_sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
        info['assets'][name]=record
    (OUT/'asset_info.json').write_text(json.dumps(info,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({name:{'size':i['native_canvas'],'used':i['used_rect']} for name,i in info['assets'].items()}))

if __name__=='__main__': main()
