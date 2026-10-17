"""Independent native-pixel QA against the original body artwork and baseline Git blobs."""
from pathlib import Path
from PIL import Image, ImageOps
import hashlib
import json
import subprocess

ROOT=Path(__file__).resolve().parents[2]
GAME=ROOT/'game'
BASELINE='a6ccf514ecfeb8503c7cfc354cb594e8742f25c0'
ART=GAME/'art_metadata/locomotion_blade_20261017'
ORIGINAL=GAME/'art_metadata/side_longblade_v07'


def git(*args):
    return subprocess.check_output(['git','-c','core.quotepath=false',*args],cwd=ROOT)


def mirror(image):
    result=Image.new(image.mode,image.size)
    result.paste(ImageOps.mirror(image),(1,0))
    return result


def main():
    failures=[]
    current_paths=json.loads((GAME/'assets/blade_paths.json').read_text(encoding='utf-8'))
    old_paths=json.loads(git('show',f'{BASELINE}:game/assets/blade_paths.json'))
    palette={tuple(bytes.fromhex(c)) for c in json.loads((ORIGINAL/'export_report.json').read_text(encoding='utf-8'))['palette']}
    protected_pixels=0
    old_wrong=0
    new_wrong=0
    for action in ['walk','run']:
        clip=f'side_view_right_{action}'
        atlas=Image.open(ORIGINAL/'edit_references'/f'{clip}.png').convert('RGBA').resize((448,384),Image.Resampling.NEAREST)
        for index in range(16):
            cell=atlas.crop((index%4*112,index//4*96,index%4*112+112,index//4*96+96))
            removed=Image.open(ORIGINAL/'weapon_masks'/clip/f'{index:02}_old.png').convert('L')
            for facing in ['right','left']:
                name=f'side_view_{facing}_{action}'
                image=Image.open(GAME/'frames'/name/f'{index:02}.png').convert('RGBA')
                original=cell if facing=='right' else mirror(cell)
                old_mask=removed if facing=='right' else mirror(removed)
                for a,b,mask in zip(image.get_flattened_data(),original.get_flattened_data(),old_mask.get_flattened_data()):
                    if b[3] and not mask:
                        protected_pixels+=1
                        if a!=b: failures.append(f'{name}/{index}: protected original body pixel changed')
                    if a[3] not in (0,255) or (a[3] and a[:3] not in palette):
                        failures.append(f'{name}/{index}: palette or alpha violation')
                sign=(1 if facing=='right' else -1)*(1 if action=='walk' else -1)
                key=f'{action}_{facing}'
                old_wrong+=old_paths['side_view'][key][index][0]*sign<=0
                new_wrong+=current_paths['side_view'][key][index][0]*sign<=0
    expected={f'game/frames/side_view_{facing}_{action}/{i:02}.png' for facing in ['left','right'] for action in ['walk','run'] for i in range(16)}
    changed=[]
    unchanged=0
    for line in git('ls-tree','-r',BASELINE,'game/frames').decode('utf-8').splitlines():
        info,path=line.split('\t',1)
        if not path.endswith('.png'):continue
        data=(ROOT/path).read_bytes()
        blob=hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
        if blob!=info.split()[2]:changed.append(path)
        else:unchanged+=1
    if set(changed)!=expected: failures.append('Changes extend outside the expected 64 locomotion frames, or a frame was missed')
    changed_keys=[k for k,v in current_paths['side_view'].items() if old_paths['side_view'][k]!=v]
    if set(changed_keys)!={'walk_left','walk_right','run_left','run_right'} or old_paths['top_down']!=current_paths['top_down']:
        failures.append('Unexpected attack or top-down blade path change')
    if new_wrong or old_wrong==0:failures.append('Direction regression was not reproduced and removed')
    result={'status':'passed' if not failures else 'failed','baseline':BASELINE,
            'protected_body_pixels_verified':protected_pixels,'changed_locomotion_frames':len(changed),
            'unchanged_other_animation_frames':unchanged,'wrong_carry_frames_before':old_wrong,
            'wrong_carry_frames_after':new_wrong,'failures':failures}
    target=GAME/'evidence/locomotion_blade_art_qa.json'
    target.parent.mkdir(parents=True,exist_ok=True)
    target.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result))
    raise SystemExit(bool(failures))


if __name__=='__main__':main()
