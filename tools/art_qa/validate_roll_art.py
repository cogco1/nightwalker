from pathlib import Path
from PIL import Image
import hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[2]
BASE='00d7057b75736b54a464bf1faf1875803c5d377c'
def main():
    failures=[];preserved=0;unique={};boxes=[]
    tree=subprocess.check_output(['git','ls-tree','-r',BASE,'game/frames'],cwd=ROOT).decode('utf8')
    for line in tree.splitlines():
        info,path=line.split('\t',1)
        if not path.endswith('.png'):continue
        data=(ROOT/path).read_bytes()
        if hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()!=info.split()[2]:failures.append('Previous frame changed: '+path)
        preserved+=1
    palette={tuple(bytes.fromhex(c)) for c in json.loads((ROOT/'game/art_metadata/side_longblade_v07/export_report.json').read_text(encoding='utf8'))['palette']}
    for direction in ['left','right']:
        unique[direction]=set()
        for i in range(16):
            path=ROOT/f'game/frames/side_view_{direction}_roll/{i:02}.png'
            im=Image.open(path).convert('RGBA');bb=im.getbbox()
            if im.size!=(112,96) or bb[3]!=84:failures.append(f'{direction}/{i}: canvas or ground contact')
            if any(p[3] not in [0,255] or (p[3] and p[:3] not in palette) for p in im.get_flattened_data()):failures.append(f'{direction}/{i}: palette/alpha/marker')
            unique[direction].add(hashlib.sha256(im.tobytes()).hexdigest())
            if direction=='right':boxes.append(list(bb))
            else:
                right=Image.open(ROOT/f'game/frames/side_view_right_roll/{i:02}.png').convert('RGBA')
                for y in range(96):
                    for x in range(1,112):
                        a,b=im.getpixel((x,y)),right.getpixel((112-x,y))
                        if a[3]!=b[3] or(a[3] and a!=b):failures.append(f'{direction}/{i}: foot-pivot mirror');break
        if len(unique[direction])!=16:failures.append('Distinct roll poses missing: '+direction)
    total=len(list((ROOT/'game/frames').glob('*/*.png')))
    if total!=1088:failures.append('Expected 1088 animation PNGs')
    report={'status':'passed' if not failures else 'failed','baseline':BASE,'previous_animation_pngs_unchanged':preserved,
        'new_roll_frames':32,'total_animation_pngs':total,'unique_poses':{k:len(v) for k,v in unique.items()},
        'native_canvas':[112,96],'pivot':[56,84],'binary_alpha':True,'palette_colors':18,'right_bounds':boxes,'failures':failures}
    (ROOT/'game/evidence/roll_art_qa.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')
    print(json.dumps(report));raise SystemExit(bool(failures))
if __name__=='__main__':main()
