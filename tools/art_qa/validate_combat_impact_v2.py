from pathlib import Path
import hashlib,subprocess,wave,json,math
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
BASE='48faf58290f6300a1f9186836920f9c34d11c782'
def main():
    failures=[];preserved={'animation_pngs':0,'previous_audio':0}
    tree=subprocess.check_output(['git','-c','core.quotepath=false','ls-tree','-r',BASE,'game/frames','game/assets/audio'],cwd=ROOT).decode('utf8')
    for row in tree.splitlines():
        info,path=row.split('\t',1)
        key='animation_pngs' if path.endswith('.png') else ('previous_audio' if path.endswith('.wav') else None)
        if key is None:continue
        data=(ROOT/path).read_bytes()
        if hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()!=info.split()[2]:failures.append('Previous asset changed: '+path)
        preserved[key]+=1
    if preserved['animation_pngs']!=1088:failures.append('Expected 1088 preserved animation PNGs')
    for filename in ['player_fx.gd','combat_feedback.gd','game_session.gd','moves_long_blade.gd']:
        folder='player' if filename in ['player_fx.gd','moves_long_blade.gd'] else 'core'
        original=subprocess.check_output(['git','show',BASE+':game/scripts/'+folder+'/'+filename],cwd=ROOT)
        archived=(ROOT/'game/art_metadata/combat_impact_v2_20261018/legacy'/(filename+'.txt')).read_bytes()
        if archived!=original:failures.append('Legacy source not preserved: '+filename)
    sounds={}
    for path in sorted((ROOT/'game/assets/audio/sfx/impact_v2').glob('*.wav')):
        with wave.open(str(path),'rb') as f:
            rate=f.getframerate();channels=f.getnchannels();width=f.getsampwidth()
            data=np.frombuffer(f.readframes(f.getnframes()),dtype='<i2').astype(float)/32768
        peak=float(np.max(np.abs(data)));seconds=len(data)/rate
        if rate!=44100 or channels!=1 or width!=2 or not 0.1<=seconds<=0.251:failures.append('Audio format/duration: '+path.name)
        if not 0.65<peak<0.68 or data[0]!=0 or data[-1]!=0:failures.append('Headroom/endpoint: '+path.name)
        sounds[path.name]={'seconds':seconds,'peak_dbfs':20*math.log10(peak),'rms_dbfs':20*math.log10(float(np.sqrt(np.mean(data*data))))}
    if len(sounds)!=6:failures.append('Expected 6 new short combat sounds')
    report={'status':'passed' if not failures else 'failed','baseline':BASE,'preserved':preserved,'legacy_source_files':4,'new_sounds':sounds,'failures':failures}
    (ROOT/'game/evidence/combat_impact_asset_qa.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')
    print(json.dumps(report));raise SystemExit(bool(failures))
if __name__=='__main__':main()
