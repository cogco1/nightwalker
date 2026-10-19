"""Build larger native-pixel fog frames and strengthen the existing ambience."""
from pathlib import Path
import importlib.util
import json
import hashlib
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'outputs/battlefield_ambient_v09'
OLD=ROOT/'outputs/battlefield_ambient_v08'
RUNTIME=ROOT/'game/assets/battlefield_ambient'

def main():
    records=json.loads((OUT/'generation_prompts.json').read_text(encoding='utf-8'))
    source=OUT/'source_art/steam_sheet.png'
    source.parent.mkdir(parents=True,exist_ok=True)
    if not source.exists(): source.write_bytes(Path(records['assets'][0]['path']).read_bytes())
    raw=Image.open(source).convert('RGBA')
    if raw.width*2!=raw.height*3: raise ValueError('Expected 3x2 equal-cell sheet')
    spec=importlib.util.spec_from_file_location('v06_assets',ROOT/'tools/build_battlefield_traversal_assets.py')
    legacy=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(legacy)
    palette,count=legacy.approved_palette()
    sheet=Image.new('RGBA',(192,128))
    frames=[]
    cw,ch=raw.width//3,raw.height//2
    for index in range(6):
        x,y=index%3,index//3
        cell=raw.crop((x*cw,y*ch,(x+1)*cw,(y+1)*ch)).resize((64,64),Image.Resampling.NEAREST)
        pixels=np.array(cell)
        pixels[:,:,3]=np.where(pixels[:,:,3]>=128,255,0)
        pixels[pixels[:,:,3]==0]=0
        bounds=Image.fromarray(pixels).getchannel('A').getbbox()
        if not bounds: raise ValueError('Empty plume frame')
        tail_y=bounds[3]-1
        tail_x=round(float(np.flatnonzero(pixels[tail_y,:,3]>0).mean()))
        shift=(24-tail_x,59-tail_y)
        aligned=Image.new('RGBA',(64,64))
        aligned.paste(Image.fromarray(pixels),shift)
        alpha=aligned.getchannel('A')
        if np.count_nonzero(np.array(alpha))!=np.count_nonzero(pixels[:,:,3]):
            raise ValueError(f'Clipped plume frame {index}: {bounds}, {shift}')
        rgb=aligned.convert('RGB').quantize(palette=palette,dither=Image.Dither.NONE).convert('RGB')
        aligned=Image.merge('RGBA',(*rgb.split(),alpha))
        sheet.paste(aligned,(x*64,y*64))
        frames.append({'index':index,'source_rect':[x*cw,y*ch,cw,ch],
            'translation':list(shift),'used_rect':list(alpha.getbbox()),
            'opaque_pixels':int(np.count_nonzero(np.array(alpha)))})
    (OUT/'asset_images').mkdir(exist_ok=True)
    path=OUT/'asset_images/steam_large.png'
    sheet.save(path,optimize=True)
    (RUNTIME/'steam_large.png').write_bytes(path.read_bytes())
    sheet.resize((1152,768),Image.Resampling.NEAREST).save(OUT/'asset_images/steam_large_preview_6x.png')
    info={'source_art':'built-in-imagegen','source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
        'native_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'frame_size':[64,64],
        'sheet_size':[192,128],'frames':frames,'emitter':[24,59],'alpha_values':[0,255],
        'palette_colors':count,'scale':1,'sampling':'nearest'}
    (OUT/'asset_info.json').write_text(json.dumps(info,indent=2)+'\n',encoding='utf-8',newline='\n')
    settings=json.loads((OLD/'ambient.json').read_text(encoding='utf-8'))
    settings.update({'version':9,'steam_texture':'res://assets/battlefield_ambient/steam_large.png',
        'steam_frame_size':[64,64],'steam_anchor':[24,59],'steam_min_alpha':0.30,'update_hz':16})
    for lamp in settings['lights']:
        layer=lamp['layer']
        lamp['period']=round(lamp['period']*0.72,3)
        lamp['min_gain']={'near':0.28,'mid':0.35,'far':0.42}[layer]
        lamp['max_gain']={'near':1.35,'mid':1.45,'far':1.55}[layer]
    for plume in settings['steam']:
        plume['period']=round(plume['period']*0.78,3)
        plume['opacity']={'near':0.56,'mid':0.38,'far':0.26}[plume['layer']]
    for star in settings['stars']:
        star['period']=round(star['period']*0.72,3)
        star['opacity']=round(min(0.65,star['opacity']*1.75),3)
    settings['dust']={'count':16,'opacity':0.32,'speed':14.0,'lengths':[1,2,3]}
    encoded=json.dumps(settings,ensure_ascii=False,indent=2)+'\n'
    for path in [OUT/'ambient.json',RUNTIME/'ambient.json']:
        path.write_text(encoded,encoding='utf-8',newline='\n')
    baseline=json.loads((OLD/'baseline_assets.json').read_text(encoding='utf-8'))
    for name,digest in baseline['sha256'].items():
        if hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=digest: raise ValueError('Protected file changed: '+name)
    baseline['base_commit']='a689e6b0b21e1cad30f30b0942428ba020ac958b'
    (OUT/'baseline_assets.json').write_text(json.dumps(baseline,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
    print(json.dumps({'frame_size':info['frame_size'],'emitter':info['emitter'],
        'used_rects':[frame['used_rect'] for frame in frames],'opaque_pixels':[frame['opaque_pixels'] for frame in frames],
        'effect_count':sum(len(settings[k]) for k in ['lights','steam','stars'])+settings['dust']['count']}))

if __name__=='__main__': main()
