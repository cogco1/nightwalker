"""Import generated committed-heavy poses with a single scale and a shared foot pivot."""
from pathlib import Path
from PIL import Image, ImageOps, ImageDraw
import json, re, hashlib, statistics
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
META=ROOT/'game/art_metadata/heavy_cleave_20261018'
PALETTE=[tuple(bytes.fromhex(c)) for c in '11141a 20242b 303842 414b58 566170 6b7480 8a8a85 33251f 533729 76513a a07a5b c5a18a e1b999 5a6268 8e999f bbc2c3 e5e8e0 75695a'.split()]
DURATIONS=[1,1,1.2,1.4,1.8,2,2,1.2,.6,.7,.9,1.8,1.6,1.3,1.05,.9]

def main():
    source=Image.open(META/'generated_heavy_cleave.png').convert('RGBA')
    a=np.asarray(source)
    occupied=(a[:,:,3]>=128).sum(axis=1)
    rows=[]
    for y,count in enumerate(occupied):
        if count>8:
            if not rows or y>rows[-1][-1]+1:rows.append([y])
            else:rows[-1].append(y)
    rows=[r for r in rows if len(r)>60]
    assert len(rows)==4, [(r[0],r[-1]) for r in rows]
    crops=[];anchors=[]
    for i in range(16):
        row=rows[i//4]
        box=(round(i%4*source.width/4),row[0],round((i%4+1)*source.width/4),row[-1]+1)
        cell=source.crop(box)
        data=np.asarray(cell)
        dark=(data[:,:,3]>=128)&(data[:,:,:3].max(axis=2)<115)
        ys,xs=np.nonzero(dark)
        ground=int(ys.max())+1
        # Register the stance from the soles, excluding the bright sword and transparent padding.
        feet=dark[max(0,ground-7):ground]
        xx=np.nonzero(feet)[1]
        anchor=(float((np.percentile(xx,5)+np.percentile(xx,95))/2),ground)
        crops.append(cell);anchors.append(anchor)
    first_box=crops[0].getchannel('A').point(lambda x:255 if x>=128 else 0).getbbox()
    scale=28/(first_box[3]-first_box[1])
    atlas=Image.new('RGBA',(112*4,96*4));records=[];paths={}
    palette=np.array(PALETTE,dtype=np.int32)
    for i,(cell,(ax,ay)) in enumerate(zip(crops,anchors)):
        frame=cell.transform((112,96),Image.Transform.AFFINE,(1/scale,0,ax-56/scale,0,1/scale,ay-84/scale),Image.Resampling.NEAREST)
        pixels=np.array(frame)
        mask=pixels[:,:,3]>=128
        colors=pixels[:,:,:3][mask].astype(np.int32)
        indices=((colors[:,None,:]-palette[None,:,:])**2).sum(axis=2).argmin(axis=1)
        pixels[:]=0;pixels[mask,:3]=palette[indices];pixels[mask,3]=255
        frame=Image.fromarray(pixels)
        assert frame.getbbox() and frame.getbbox()[0]>0 and frame.getbbox()[2]<112
        steel=mask&((pixels[:,:,0]>=140)&(pixels[:,:,1]>=150)&(pixels[:,:,2]>=150))
        yy,xx=np.nonzero(steel)
        assert len(xx)>0, i
        chosen=int(np.argmin(xx)) if i in [2,4,5,6,7] else int(np.argmin(yy)) if i==3 else int(np.argmax(xx))
        tip=[int(xx[chosen])-56,int(yy[chosen])-84]
        for facing in ['right','left']:
            out=frame
            if facing=='left':
                out=Image.new('RGBA',(112,96));out.alpha_composite(ImageOps.mirror(frame),(1,0))
            folder=ROOT/f'game/frames/side_view_{facing}_heavy_cleave';folder.mkdir(parents=True,exist_ok=True)
            out.save(folder/f'{i:02}.png')
            paths.setdefault('heavy_cleave_'+facing,[]).append(tip if facing=='right' else [-tip[0],tip[1]])
        atlas.alpha_composite(frame,(i%4*112,i//4*96))
        records.append({'frame':i,'source_anchor':[ax,ay],'native_bbox':list(frame.getbbox()),'tip_from_pivot':tip,'sha256':hashlib.sha256(frame.tobytes()).hexdigest()})
    assert len({r['sha256'] for r in records})==16
    atlas.save(META/'heavy_cleave_native.png')
    review=Image.new('RGB',atlas.size,'#242a33');review.paste(atlas,mask=atlas.getchannel('A'))
    review.resize((1344,1152),Image.Resampling.NEAREST).save(META/'native_review.png')
    resource=ROOT/'game/assets/side_view.tres';text=resource.read_text(encoding='utf8')
    if 'side_view_right_heavy_cleave' not in text:
        text=re.sub(r'load_steps=(\d+)',lambda m:'load_steps='+str(int(m[1])+32),text,count=1)
        ext=[];clips=[]
        for facing in ['left','right']:
            frames=[]
            for i,duration in enumerate(DURATIONS):
                rid=f'heavy_cleave_{facing}_{i:02}'
                ext.append(f'[ext_resource type="Texture2D" path="res://frames/side_view_{facing}_heavy_cleave/{i:02}.png" id="{rid}"]')
                frames.append('{"duration":'+str(duration)+',"texture":ExtResource("'+rid+'")}')
            clips.append('{"frames":['+', '.join(frames)+'],"loop":false,"name":&"heavy_cleave_'+facing+'","speed":32.0}')
        text=text.replace('[resource]','\n'.join(ext)+'\n\n[resource]',1)
        index=text.rfind(']');text=text[:index].rstrip()+', '+', '.join(clips)+'\n]'+text[index+1:]
        resource.write_text(text,encoding='utf8',newline='\n')
    bp=ROOT/'game/assets/blade_paths.json';bptext=bp.read_text(encoding='utf8')
    for name,points in paths.items():
        value=json.dumps(points,separators=(',',':'))
        match=re.search(r'"'+name+r'"\s*:\s*',bptext)
        if match:
            _,length=json.JSONDecoder().raw_decode(bptext[match.end():])
            bptext=bptext[:match.end()]+value+bptext[match.end()+length:]
        else:
            bptext=bptext.replace('"side_view": {','"side_view": {\n\t\t"'+name+'": '+value+',',1)
    bp.write_text(bptext,encoding='utf8',newline='\n')
    report={'mode':'built-in image_gen','native_canvas':[112,96],'pivot':[56,84],'uniform_scale':float(scale),'palette':18,
        'frame_duration_units':DURATIONS,'fps':32,'windup_seconds':sum(DURATIONS[:8])/32,'stroke_seconds':sum(DURATIONS[8:11])/32,
        'clip_seconds':sum(DURATIONS)/32,'new_frames':32,'left_mirror_axis':56,'frames':records}
    (META/'import.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf8',newline='\n')
    print(json.dumps({k:v for k,v in report.items() if k!='frames'}))

if __name__=='__main__':main()
