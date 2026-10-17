"""Build continuous charge follow-up entries from existing, unmodified drawn poses."""
from pathlib import Path
import json,re

ROOT=Path(__file__).resolve().parents[2]
CLIP=re.compile(r'\{\s*"frames"\s*:\s*\[(.*?)\],\s*"loop"\s*:\s*(true|false),\s*"name"\s*:\s*&"([^"]+)",\s*"speed"\s*:\s*([0-9.]+)\s*\}',re.S)
LIGHT_START=[.45,.45,.55,.6,.6,.6,.7]
LINKS={
 'charge_link_light':{'fps':40.0,'sources':[('charged_draw',11),('charged_draw',12),('attack2',0)]+[('attack2',i) for i in range(3,16)],'duration':[.8,.8,.5,.55,.6,.65]+[.85]*4+[1.05]*3+[.95]*3,'active':[6,9]},
 'charge_link_heavy':{'fps':32.0,'sources':[('charged_draw',11),('charged_draw',12)]+[('heavy_cleave',i) for i in [1,2,3,4,5,7,8,9,10,11,12,13,14,15]],'duration':[.65,.65,.5,.55,.65,.75,.8,.8,.6,.7,.9,1.8,1.6,1.3,1.05,.9],'active':[8,10]},
}

def main():
 retimed=[]
 for resource in ['side_view','top_down']:
  path=ROOT/f'game/assets/{resource}.tres';text=path.read_text(encoding='utf8')
  def timing(m):
   if not re.fullmatch(r'attack1_(left|right|up|down)',m[3]):return m[0]
   index=0
   def duration(d):
    nonlocal index
    value=LIGHT_START[index] if index<len(LIGHT_START) else float(d[1]);index+=1
    return '"duration": '+str(value)
   body=re.sub(r'"duration"\s*:\s*([0-9.]+)',duration,m[1]);assert index==16
   retimed.append(resource+'/'+m[3])
   return '{\n"frames": ['+body+'],\n"loop": '+m[2]+',\n"name": &"'+m[3]+'",\n"speed": '+m[4]+'\n}'
  text=CLIP.sub(timing,text);path.write_text(text,encoding='utf8',newline='\n')
 assert len(retimed)==6
 path=ROOT/'game/assets/side_view.tres';text=path.read_text(encoding='utf8')
 ids={p:i for p,i in re.findall(r'\[ext_resource type="Texture2D" path="([^"]+)" id="([^"]+)"\]',text)}
 paths_file=ROOT/'game/assets/blade_paths.json';paths=json.loads(paths_file.read_text(encoding='utf8'))
 blocks={}
 for prefix,row in LINKS.items():
  assert len(row['sources'])==len(row['duration'])==16
  for facing in ['left','right']:
   name=prefix+'_'+facing;frames=[];tips=[]
   for (source,index),duration in zip(row['sources'],row['duration']):
    resource=ids[f'res://frames/side_view_{facing}_{source}/{index:02}.png']
    frames.append('{"duration":'+str(duration)+',"texture":ExtResource("'+resource+'")}')
    tips.append(paths['side_view'][source+'_'+facing][index])
   blocks[name]='{"frames":['+', '.join(frames)+'],"loop":false,"name":&"'+name+'","speed":'+str(row['fps'])+'}'
   paths['side_view'][name]=tips
 existing=set()
 def update(m):
  if m[3] not in blocks:return m[0]
  existing.add(m[3]);return blocks[m[3]]
 text=CLIP.sub(update,text)
 extra=[block for name,block in blocks.items() if name not in existing]
 if extra:
  end=text.rfind('\n]');assert end>0;text=text[:end]+', '+', '.join(extra)+text[end:]
 path.write_text(text,encoding='utf8',newline='\n')
 if json.loads(paths_file.read_text(encoding='utf8')) != paths:
  paths_file.write_text(json.dumps(paths,indent=2)+'\n',encoding='utf8',newline='\n')
 meta=ROOT/'game/art_metadata/combat_links_20261018';meta.mkdir(parents=True,exist_ok=True)
 report={'hold_threshold_seconds':.24,'full_charge_seconds':.55,'ground_light_first_contact_seconds':sum(LIGHT_START)/36,'retimed_clips':retimed,'links':LINKS,'new_animation_entries':4,'new_pngs':0,'original_pngs_preserved':1152}
 (meta/'timing.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf8',newline='\n')
 print(json.dumps({'retimed':len(retimed),'link_entries':4,'light_windup':sum(LIGHT_START)/36,'linked_light_windup':sum(LINKS['charge_link_light']['duration'][:6])/40,'linked_heavy_windup':sum(LINKS['charge_link_heavy']['duration'][:8])/32}))

if __name__=='__main__':main()
