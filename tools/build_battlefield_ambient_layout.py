"""Serialize reviewed source-pixel effect anchors without changing map geometry."""
from pathlib import Path
import json
import hashlib
import subprocess

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'outputs/battlefield_ambient_v08'
RUNTIME=ROOT/'game/assets/battlefield_ambient'

def main():
    reviewed=json.loads((OUT/'anchor_suggestions.json').read_text(encoding='utf-8'))
    settings={'version':8,'steam_texture':'res://assets/battlefield_ambient/steam.png',
        'steam_frames':[3,2],'steam_anchor':[16,29]}
    for kind in ['lights','steam','stars']:
        settings[kind]=[{key:value for key,value in item.items() if key!='note'} for item in reviewed[kind]
                        if kind!='stars' or item['position'][0]<=1951]
    # Six connected plume poses should visibly develop while running past a vent;
    # the more distant sources retain slower cycles than the nearby exhausts.
    for plume in settings['steam']:
        plume['period']=round(plume['period']*0.5,3)
    settings['dust']={'count':10,'opacity':0.16,'speed':5.0}
    settings['evidence_cameras']=[[400,104],[1008,-106],[5120,-149]]
    encoded=json.dumps(settings,ensure_ascii=False,indent=2)+'\n'
    RUNTIME.mkdir(parents=True,exist_ok=True)
    for path in [RUNTIME/'ambient.json',OUT/'ambient.json']:
        path.write_text(encoded,encoding='utf-8',newline='\n')
    protected=['game/assets/battlefield_layer_01/battlefield_layer_01_native.png',
        'game/assets/battlefield_mid_background/battlefield_mid_native.png',
        'game/assets/battlefield_far_background/battlefield_far_native.png',
        'game/assets/battlefield_traversal/foreground_native.png',
        'game/assets/battlefield_traversal/layout.json','game/scripts/player/player.gd',
        'game/scripts/battlefield_elevator.gd','game/project.godot']
    hashes={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in protected}
    for name,digest in hashes.items():
        committed=subprocess.check_output(['git','show','6727560ced65d6774f195bda4f9bde3cbe6f214f:'+name],cwd=ROOT)
        # Git stores source text with LF; compare the working source canonically.
        working=(ROOT/name).read_bytes()
        if not name.endswith('.png'): working=working.replace(b'\r\n',b'\n')
        if working!=committed: raise ValueError('Protected baseline changed: '+name)
    (OUT/'baseline_assets.json').write_text(json.dumps({'base_commit':'6727560ced65d6774f195bda4f9bde3cbe6f214f',
        'unchanged':True,'sha256':hashes},ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
    print(json.dumps({kind:len(settings[kind]) for kind in ['lights','steam','stars']}|{'dust':settings['dust']['count'],'protected_files':len(hashes)}))

if __name__=='__main__': main()
