from pathlib import Path
from PIL import Image
import hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[2]
GAME=ROOT/'game'
BASE='aca1c28f38a0e40cd32cec39f2cc849783bd5f0a'


def main():
    failures=[]
    palette={tuple(bytes.fromhex(c)) for c in json.loads((GAME/'art_metadata/side_longblade_v07/export_report.json').read_text(encoding='utf-8'))['palette']}
    preserved=0
    tree=subprocess.check_output(['git','-c','core.quotepath=false','ls-tree','-r',BASE,'game/frames'],cwd=ROOT).decode('utf-8')
    for line in tree.splitlines():
        info,path=line.split('\t',1)
        if not path.endswith('.png'):continue
        data=(ROOT/path).read_bytes()
        actual=hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
        if actual!=info.split()[2]:failures.append('Previously approved frame changed: '+path)
        preserved+=1
    unique={}
    for facing in ['right','left']:
        unique[facing]=set()
        for i in range(16):
            path=GAME/'frames'/f'side_view_{facing}_crouch_walk'/f'{i:02}.png'
            image=Image.open(path).convert('RGBA')
            if image.size!=(112,96) or image.getbbox()[3]!=84:failures.append(str(path)+': canvas/foot anchor')
            for pixel in image.get_flattened_data():
                if pixel[3] not in [0,255] or(pixel[3] and pixel[:3] not in palette):failures.append(str(path)+': palette/alpha')
            unique[facing].add(hashlib.sha256(image.tobytes()).hexdigest())
        if len(unique[facing])!=16:failures.append('Missing distinct crouch steps: '+facing)
    total=len(list((GAME/'frames').glob('*/*.png')))
    if total!=1088:failures.append('Expected 1088 total frames including rolls')
    report={'status':'passed' if not failures else 'failed','baseline':BASE,'original_animation_pngs_unchanged':preserved,
            'new_crouch_frames':32,'total_animation_pngs':total,'unique_new_poses_per_facing':{k:len(v) for k,v in unique.items()},
            'native_canvas':[112,96],'foot_pivot':[56,84],'binary_alpha':True,'existing_palette_only':True,'failures':failures}
    (GAME/'evidence/shift_art_qa.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report))
    raise SystemExit(bool(failures))


if __name__=='__main__':main()
