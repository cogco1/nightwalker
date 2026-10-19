"""Align imagegen steam animation to six 32px cells with fixed emission points."""
from pathlib import Path
import hashlib
import importlib.util
import json
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'outputs/battlefield_ambient_v08'
RUNTIME=ROOT/'game/assets/battlefield_ambient'

def main():
    record=json.loads((OUT/'generation_prompts.json').read_text(encoding='utf-8'))
    source=OUT/'source_art/steam_sheet.png'
    source.parent.mkdir(parents=True,exist_ok=True)
    if not source.exists(): source.write_bytes(Path(record['assets'][0]['path']).read_bytes())
    image=Image.open(source).convert('RGBA')
    if image.width*2 != image.height*3: raise ValueError('Expected a 3-column 2-row equal-cell sheet')
    spec=importlib.util.spec_from_file_location('v06_assets',ROOT/'tools/build_battlefield_traversal_assets.py')
    legacy=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(legacy)
    palette,count=legacy.approved_palette()
    sheet=Image.new('RGBA',(96,64))
    frames=[]
    cw,ch=image.width//3,image.height//2
    for index in range(6):
        x,y=index%3,index//3
        frame=image.crop((x*cw,y*ch,(x+1)*cw,(y+1)*ch)).resize((32,32),Image.Resampling.NEAREST)
        pixels=np.array(frame)
        pixels[:,:,3]=np.where(pixels[:,:,3]>=128,255,0)
        pixels[pixels[:,:,3]==0]=0
        frame=Image.fromarray(pixels)
        bounds=frame.getchannel('A').getbbox()
        if not bounds: raise ValueError(f'Empty steam frame {index}')
        # Emission point is chosen from the lowest surviving tail pixels, then
        # translated on the integer grid; the plume is never stretched per frame.
        tail=np.array(frame.getchannel('A'))
        anchor_y=bounds[3]-1
        anchor_x=round(float(np.flatnonzero(tail[anchor_y]>0).mean()))
        offset=(16-anchor_x,29-anchor_y)
        aligned=Image.new('RGBA',(32,32))
        aligned.paste(frame,offset)
        alpha=aligned.getchannel('A')
        rgb=aligned.convert('RGB').quantize(palette=palette,dither=Image.Dither.NONE).convert('RGB')
        aligned=Image.merge('RGBA',(*rgb.split(),alpha))
        sheet.paste(aligned,(x*32,y*32))
        frames.append({'index':index,'source_rect':[x*cw,y*ch,cw,ch],
                       'native_bounds_before_align':list(bounds),'native_translation':list(offset),
                       'emitter':[16,29],'used_rect':list(aligned.getchannel('A').getbbox())})
    RUNTIME.mkdir(parents=True,exist_ok=True)
    (OUT/'asset_images').mkdir(exist_ok=True)
    path=OUT/'asset_images/steam.png'
    sheet.save(path,optimize=True)
    (RUNTIME/'steam.png').write_bytes(path.read_bytes())
    sheet.resize((768,512),Image.Resampling.NEAREST).save(OUT/'asset_images/steam_preview_8x.png')
    info={'source_art':'built-in-imagegen','source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
          'native_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
          'sheet_size':[96,64],'frame_size':[32,32],'hframes':3,'vframes':2,'palette_colors':count,
          'alpha_values':sorted(np.unique(np.array(sheet)[:,:,3]).tolist()),'sampling':'nearest',
          'emitter':[16,29],'frames':frames}
    (OUT/'asset_info.json').write_text(json.dumps(info,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(info))

if __name__=='__main__': main()
