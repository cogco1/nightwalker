"""Register the authored hospital to the original character's1:1 pixel grid."""
from pathlib import Path
import hashlib
import json
import shutil
from PIL import Image

HERE=Path(__file__).resolve().parent
GAME=next((p for p in HERE.parents if (p/'project.godot').is_file()),HERE.parents[2]/'game_v11')


def main():
    source=HERE/'hospital_source_selected.png'
    raw=Image.open(source).convert('RGB')
    manifest=json.loads((HERE/'generation_manifest.json').read_text(encoding='utf-8'))
    native_size=tuple(manifest['native_size'])
    sampled=raw.resize(native_size,Image.Resampling.NEAREST)
    palette_values=sampled.quantize(colors=32,dither=Image.Dither.NONE).getpalette()[:96]
    # Keep tiny cyan screen and red power indicators readable in the large map.
    cyan=[];red=[]
    channels=iter(sampled.tobytes())
    for r,g,b in zip(channels,channels,channels):
        if g>95 and b>100 and g>r*1.35 and b>r*1.35:
            cyan.append((r,g,b))
        if r>65 and r>g*1.45 and r>b*1.25:
            red.append((r,g,b))
    for samples in [cyan,red]:
        image=Image.new('RGB',(max(1,len(samples)),1))
        if samples:
            image.putdata(samples)
        palette_values+=image.quantize(colors=4,dither=Image.Dither.NONE).getpalette()[:12]
    palette=Image.new('P',(1,1))
    palette.putpalette(palette_values+palette_values[-3:]*(256-len(palette_values)//3))
    native=sampled.quantize(palette=palette,dither=Image.Dither.NONE).convert('RGB')
    target=GAME/'assets/underground_hospital'
    target.mkdir(parents=True,exist_ok=True)
    native.save(target/'hospital_native.png')
    native.save(HERE/'hospital_native.png')
    native.resize((native.width*2,native.height*2),Image.Resampling.NEAREST).save(HERE/'hospital_overview_2x_v11.png')
    side_source=HERE/'hospital_side_source.png'
    if side_source.is_file():
        side=Image.open(side_source).convert('RGB').resize(native_size,Image.Resampling.NEAREST).quantize(palette=palette,dither=Image.Dither.NONE).convert('RGB')
        side.save(target/'hospital_side_native.png')
        side.save(HERE/'hospital_side_native.png')
        side.resize((side.width*2,side.height*2),Image.Resampling.NEAREST).save(HERE/'hospital_side_overview_2x_v11.png')
    for floor in [1,2]:
        floor_source=HERE/f'hospital_floor_{floor}_source.png'
        if floor_source.is_file():
            result=Image.open(floor_source).convert('RGB').resize((640,224),Image.Resampling.NEAREST).quantize(palette=palette,dither=Image.Dither.NONE).convert('RGB')
            result.save(target/f'hospital_floor_{floor}_native.png')
            result.save(HERE/f'hospital_floor_{floor}_native.png')
            result.resize((1280,448),Image.Resampling.NEAREST).save(HERE/f'hospital_floor_{floor}_preview_2x_v11.png')
    manifest.update(source_size=list(raw.size),native_size=list(native_size),viewport=[320,180],
        source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
        native_sha256=hashlib.sha256((target/'hospital_native.png').read_bytes()).hexdigest(),
        native_palette_colors=len(native.getcolors(native.width*native.height)),
        technical_processing='nearest native registration,40-color reserved indicator palette,no dithering;world1:1;camera1;original character textures unchanged')
    (HERE/'generation_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    metadata=GAME/'art_metadata/underground_hospital_v11'
    if metadata.resolve()!=HERE.resolve():
        shutil.copytree(HERE,metadata,dirs_exist_ok=True,ignore=shutil.ignore_patterns('__pycache__','hospital_large_native_inspect.png'))
    print(json.dumps({'status':'exported','native':list(native_size),'viewport':[320,180],'colors':manifest['native_palette_colors'],'npc_instances':0}))


if __name__=='__main__':
    main()
