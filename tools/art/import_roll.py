"""Import authored roll poses. Uniform scale, palette snapping, fixed ground pivot; no pose synthesis."""
from pathlib import Path
from PIL import Image, ImageOps, ImageDraw
import json, statistics, shutil

ROOT = Path(__file__).resolve().parents[2]
META = ROOT/'game/art_metadata/roll_thrust_20261018'
SOURCE = META/'generated_roll.png'
PALETTE = [tuple(bytes.fromhex(c)) for c in '11141a 20242b 303842 414b58 566170 6b7480 8a8a85 33251f 533729 76513a a07a5b c5a18a e1b999 5a6268 8e999f bbc2c3 e5e8e0 75695a'.split()]
MARKERS = [(176,292.5),(516.5,292.5),(840.5,292.5),(1181.5,292.5),
           (176,571.5),(516.5,571.5),(840.5,571.5),(1181.5,571.5),
           (176,841.5),(516.5,841.5),(840.5,841.5),(1181.5,841.5),
           (176,1104),(516.5,1104),(840.5,1104),(1181.5,1104)]

def main():
    META.mkdir(parents=True,exist_ok=True)
    im=Image.open(SOURCE).convert('RGBA')
    p=im.load()
    for y in range(im.height):
        for x in range(im.width):
            r,g,b,a=p[x,y]
            if a<128 or (r>95 and b>90 and g<max(r,b)*.65): p[x,y]=(0,0,0,0)
    rows=[0,310,590,865,1161]
    crops=[]
    for i,(mx,my) in enumerate(MARKERS):
        col,row=i%4,i//4
        bounds=(round(col*im.width/4),rows[row],round((col+1)*im.width/4),round(my-8))
        crop=im.crop(bounds)
        bb=crop.getbbox()
        crops.append((crop.crop(bb),(mx-bounds[0]-bb[0],my-bounds[1]-bb[1])))
    # Stable size for all poses; measure only upright frames, never inflate a tucked pose to standing height.
    scale=statistics.median(crops[i][0].height for i in [0,14,15])/28.0
    records=[];atlas=Image.new('RGBA',(112*4,96*4))
    for i,(crop,marker) in enumerate(crops):
        resized=crop.resize((round(crop.width/scale),round(crop.height/scale)),Image.Resampling.NEAREST)
        out=Image.new('RGBA',(112,96))
        px=resized.load()
        for y in range(resized.height):
            for x in range(resized.width):
                r,g,b,a=px[x,y]
                if a:
                    color=min(PALETTE,key=lambda c:(c[0]-r)**2+(c[1]-g)**2+(c[2]-b)**2)
                    px[x,y]=(*color,255)
        position=(round(56-marker[0]/scale),84-resized.height)
        out.alpha_composite(resized,position)
        folder=ROOT/'game/frames/side_view_right_roll';folder.mkdir(exist_ok=True)
        out.save(folder/f'{i:02}.png')
        # x' = 2*56 - x: mirror about the foot pivot, not the 55.5px canvas center.
        mirrored=Image.new('RGBA',out.size)
        mirrored.alpha_composite(ImageOps.mirror(out),(1,0))
        folder=ROOT/'game/frames/side_view_left_roll';folder.mkdir(exist_ok=True)
        mirrored.save(folder/f'{i:02}.png')
        atlas.alpha_composite(out,(i%4*112,i//4*96))
        records.append({'frame':i,'source_size':list(crop.size),'bounds':list(out.getbbox()),'uniform_source_scale':scale})
    atlas.save(META/'roll_atlas_native.png')
    (META/'import.json').write_text(json.dumps({'mode':'builtin image_gen','native_canvas':[112,96],'pivot':[56,84],
        'palette':18,'uniform_scale':scale,'frames':records,'left':'right mirrored around x=56; no resizing per pose'},indent=2)+'\n',encoding='utf8')
    resource=ROOT/'game/assets/side_view.tres'
    text=resource.read_text(encoding='utf8')
    if 'side_view_right_roll' not in text:
        import re
        text=re.sub(r'load_steps=(\d+)',lambda m:f'load_steps={int(m[1])+32}',text,count=1)
        ext=[];anims=[]
        for direction in ['left','right']:
            frames=[]
            for i in range(16):
                rid=f'roll_{direction}_{i:02}'
                ext.append(f'[ext_resource type="Texture2D" path="res://frames/side_view_{direction}_roll/{i:02}.png" id="{rid}"]')
                frames.append('{\n"duration": 1.0,\n"texture": ExtResource("'+rid+'")\n}')
            anims.append('{\n"frames": ['+', '.join(frames)+'],\n"loop": false,\n"name": &"roll_'+direction+'",\n"speed": 53.3333333333\n}')
        text=text.replace('[resource]','\n'.join(ext)+'\n\n[resource]',1)
        index=text.rfind(']')
        text=text[:index].rstrip()+', '+', '.join(anims)+'\n]'+text[index+1:]
        resource.write_text(text,encoding='utf8',newline='\n')
    print(json.dumps({'uniform_scale':scale,'poses':[c[0].size for c in crops],'frames_written':32}))

if __name__=='__main__':main()
