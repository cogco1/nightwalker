"""Import a generated crouch walk at the existing native pixel size and foot anchor."""
from pathlib import Path
from statistics import median
import json,hashlib,re
from PIL import Image,ImageOps,ImageDraw
ROOT=Path(__file__).resolve().parents[2]
GAME=ROOT/'game'
ART=GAME/'art_metadata/crouch_walk_20261018'


def main():
    source=Image.open(ART/'generated_crouch_walk.png').convert('RGBA')
    histogram=[sum(source.getpixel((x,y))[3]>=128 for x in range(source.width)) for y in range(source.height)]
    bands=[]
    for y,count in enumerate(histogram):
        if count>8:
            if not bands or y>bands[-1][-1]+1:bands.append([y])
            else:bands[-1].append(y)
    bands=[b for b in bands if len(b)>40]
    if len(bands)!=4:raise ValueError(f'Expected four complete atlas rows, got {len(bands)}')
    cells=[]
    for i in range(16):
        left=round(i%4*source.width/4)
        right=round((i%4+1)*source.width/4)
        row=bands[i//4]
        cell=source.crop((left,row[0],right,row[-1]+1))
        mask=cell.getchannel('A').point(lambda a:255 if a>=128 else 0)
        mark=[(x,y) for y in range(cell.height) for x in range(cell.width) if (p:=cell.getpixel((x,y)))[3]>=128 and p[0]>180 and p[2]>120 and p[1]<90]
        if not mark:raise ValueError(f'Missing wrist registration marker in cell {i}')
        wrist=(sum(p[0] for p in mark)/len(mark),sum(p[1] for p in mark)/len(mark))
        cells.append((cell,mask.getbbox(),wrist))
    scale=15/median(box[3]-box[1] for cell,box,wrist in cells)
    palette=[tuple(bytes.fromhex(c)) for c in json.loads((GAME/'art_metadata/side_longblade_v07/export_report.json').read_text(encoding='utf-8'))['palette']]
    blade=Image.open(GAME/'art_metadata/locomotion_blade_20261017/carry_blade_native.png').convert('RGBA')
    records=[]
    for i,(cell,box,wrist) in enumerate(cells):
        for y in range(cell.height):
            for x in range(cell.width):
                p=cell.getpixel((x,y))
                if p[3]<128:cell.putpixel((x,y),(0,0,0,0))
                elif p[0]>140 and p[2]>90 and p[1]<110:cell.putpixel((x,y),(*palette[0],255))
        # The front grip remains at x=63; the soles remain exactly one pixel above the foot pivot.
        transform=(1/scale,0,wrist[0]-63/scale,0,1/scale,box[3]-84/scale)
        frame=cell.transform((112,96),Image.Transform.AFFINE,transform,Image.Resampling.NEAREST)
        for y in range(96):
            for x in range(112):
                p=frame.getpixel((x,y))
                if p[3]:
                    c=min(palette,key=lambda c:sum((a-b)**2 for a,b in zip(p[:3],c)))
                    frame.putpixel((x,y),(*c,255))
        native_wrist=(63,round(84+(wrist[1]-box[3])*scale))
        weapon=Image.new('RGBA',(112,96))
        weapon.paste(blade,(native_wrist[0]-2,native_wrist[1]-1))
        result=Image.alpha_composite(weapon,frame)
        for facing in ['right','left']:
            current=result
            if facing=='left':
                current=Image.new('RGBA',(112,96))
                current.paste(ImageOps.mirror(result),(1,0))
            target=GAME/'frames'/f'side_view_{facing}_crouch_walk'/f'{i:02}.png'
            target.parent.mkdir(parents=True,exist_ok=True)
            current.save(target)
        records.append({'frame':i,'source_box':box,'source_wrist':wrist,'native_wrist':native_wrist,'body_bbox':frame.getbbox(),'body_height':frame.getbbox()[3]-frame.getbbox()[1],
                        'sha256':hashlib.sha256(result.tobytes()).hexdigest()})
    if len({r['sha256'] for r in records})<12:raise ValueError('Crouch walk lacks distinct step poses')
    resource=GAME/'assets/side_view.tres'
    text=resource.read_text(encoding='utf-8')
    if 'crouch_walk_right' not in text:
        loads=[];animations=[]
        for facing in ['left','right']:
            for i in range(16):loads.append(f'[ext_resource type="Texture2D" path="res://frames/side_view_{facing}_crouch_walk/{i:02}.png" id="side_view_{facing}_crouch_walk_{i}"]')
            frames=',\n'.join('{'+'"duration":1.0,"texture":ExtResource("side_view_'+facing+'_crouch_walk_'+str(i)+'")}' for i in range(16))
            animations.append('{"frames":['+frames+'],"loop":true,"name":&"crouch_walk_'+facing+'","speed":14.0}')
        text=re.sub(r'load_steps=(\d+)',lambda m:'load_steps='+str(int(m.group(1))+32),text,count=1)
        end_header=text.index('\n\n')
        text=text[:end_header]+ '\n\n'+'\n'.join(loads)+text[end_header:]
        end_animations=text.rfind(']')
        text=text[:end_animations].rstrip()+',\n'+',\n'.join(animations)+'\n'+text[end_animations:]
        resource.write_text(text,encoding='utf-8',newline='\n')
    preview=Image.new('RGB',(4*240,4*124),'#202633')
    draw=ImageDraw.Draw(preview)
    for i in range(16):
        frame=Image.open(GAME/'frames/side_view_right_crouch_walk'/f'{i:02}.png').convert('RGBA').crop((36,63,92,87)).resize((224,96),Image.Resampling.NEAREST)
        preview.paste(frame,(i%4*240+8,i//4*124+22),frame)
        draw.text((i%4*240+8,i//4*124+4),f'{i:02}',fill='white')
    preview.save(ART/'native_review.png')
    report={'generator':'built-in image_gen','native_canvas':[112,96],'pivot':[56,84],'fps':14,'frames':records,'single_global_scale':scale,'total_new_png_frames':32,
            'registration_marker_removed':True,'blade_source':'../locomotion_blade_20261017/carry_blade_native.png'}
    (ART/'import_report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'new_frames':32,'body_heights':[r['body_height'] for r in records],'distinct_poses':len({r['sha256'] for r in records})}))


if __name__=='__main__':main()
