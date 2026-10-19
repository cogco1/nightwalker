"""Compose denser industrial terrain from generated pixel modules; keep v06 route."""
from pathlib import Path
import json
import hashlib
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'outputs/battlefield_density_v07'
ASSETS=ROOT/'game/assets/battlefield_traversal'
ORIGIN=(0,-256)
GROUND=168

DECKS={
    'warehouse':[('roof',[31,77,200,5]),('second_floor',[56,130,176,5]),('left_landing',[0,140,42,5])],
    'refinery':[('upper_catwalk',[60,117,169,5]),('lower_catwalk',[0,179,233,5]),
                ('upper_landing',[247,137,9,4]),('lower_landing',[240,194,16,4])],
    'megafactory':[('left_roof',[8,67,182,5]),('raised_roof',[194,75,70,5]),
                   ('main_roof',[264,91,695,5]),('second_floor_left',[199,202,97,5]),
                   ('second_floor',[300,194,569,5]),('east_catwalk',[876,215,141,5])]
}
INFILL=[('warehouse_01','warehouse',1856),('refinery_01','refinery',2136),
        ('warehouse_02','warehouse',2440),('refinery_02','refinery',2728),
        ('warehouse_03','warehouse',2992),('warehouse_04','warehouse',3512),
        ('refinery_03','refinery',3808),('warehouse_05','warehouse',4096),
        ('refinery_04','refinery',4672),('mega_01','megafactory',5088)]
PATCHES=[('ground_grating',1088),('ground_concrete',1856),('ground_covers',2440),
         ('ground_grating',3072),('ground_concrete',3776),('ground_covers',4416),
         ('ground_grating',5024),('ground_concrete',5536)]

def main():
    data=json.loads((ROOT/'outputs/battlefield_traversal_v06/layout.json').read_text(encoding='utf-8'))
    data['version']=7
    # Move the final old gatehouse out of the new elevator corridor.
    for fixture in data['fixtures']:
        if fixture['id']=='gate_03':
            fixture['position'][0]-=384
            fixture['rect'][0]-=384
    for collider in data['colliders']:
        if collider['fixture_id']=='gate_03':
            if 'rect' in collider: collider['rect'][0]-=384
            else:
                for p in collider['polygon']: p[0]-=384
    for identity,name,x in INFILL:
        art=Image.open(ASSETS/(name+'.png'))
        y=GROUND-art.height
        fixture={'id':identity,'asset':name+'.png','kind':'building','position':[x,y],
                 'rect':[x,y,art.width,art.height],'surfaces':[]}
        for surface,rect in DECKS[name]:
            lx,ly,w,h=rect
            sid=identity+'_'+surface
            data['colliders'].append({'id':sid,'rect':[x+lx,y+ly,w,h],'one_way':True,
                'kind':'roof' if 'roof' in surface else 'floor','fixture_id':identity})
            fixture['surfaces'].append(sid)
        if name=='refinery':
            for label,points in [('upper',[(229,117),(249,137),(249,142),(229,122)]),
                                 ('middle',[(229,179),(250,194),(250,199),(229,184)]),
                                 ('lower',[(228,223),(253,255),(253,260),(228,228)])]:
                sid=identity+'_stairs_'+label
                data['colliders'].append({'id':sid,'polygon':[[x+px,y+py] for px,py in points],
                    'one_way':True,'kind':'stairs','fixture_id':identity})
                fixture['surfaces'].append(sid)
        data['fixtures'].append(fixture)
    canvas=Image.new('RGBA',(6144,512))
    materials=[]
    for index,(name,x) in enumerate(PATCHES):
        art=Image.open(ASSETS/(name+'.png')).convert('RGBA')
        # Crop only the transparent rows above the finished flat material strip;
        # the native pixel content is neither stretched nor raised above y168.
        bounds=art.getchannel('A').getbbox()
        art=art.crop((0,bounds[1],art.width,art.height))
        canvas.alpha_composite(art,(x,GROUND-ORIGIN[1]))
        materials.append({'id':'surface_'+str(index+1),'asset':name+'.png',
            'position':[x,GROUND],'source_crop':[0,bounds[1],art.width,bounds[3]],'collision':'original ground'})
    # Building facades behind cars; the hero remains above the complete foreground.
    for fixture in sorted(data['fixtures'],key=lambda f:f['kind']=='vehicle'):
        x,y=fixture['position']
        canvas.alpha_composite(Image.open(ASSETS/fixture['asset']).convert('RGBA'),(x,y-ORIGIN[1]))
    shaft=Image.open(ASSETS/'lift_shaft.png').convert('RGBA')
    canvas.alpha_composite(shaft,(5024,-152-ORIGIN[1]))
    data['ground_materials']=materials
    data['elevator']={'id':'mill_lift','x':5040,'width':64,'bottom_y':168,'top_y':-85,
        'speed':40,'deck_height':4,'call_range':28,
        'sprite':'res://assets/battlefield_traversal/industrial_lift.png','sprite_offset':[0,-55],
        'landing_surface_id':'mega_01_left_roof'}
    data['elevator_shaft']={'asset':'lift_shaft.png','position':[5024,-152]}
    OUT.mkdir(parents=True,exist_ok=True)
    for path in [ASSETS/'foreground_native.png',OUT/'foreground_native.png']: canvas.save(path,optimize=True)
    canvas.resize((12288,1024),Image.Resampling.NEAREST).save(OUT/'foreground_12288x1024.png',optimize=True)
    encoded=json.dumps(data,ensure_ascii=False,indent=2)+'\n'
    for path in [ASSETS/'layout.json',OUT/'layout.json']:
        with path.open('w',encoding='utf-8',newline='\n') as stream: stream.write(encoded)
    report={'version':7,'art_size':[6144,512],'origin':list(ORIGIN),
        'buildings':sum(f['kind']=='building' for f in data['fixtures']),
        'vehicles':sum(f['kind']=='vehicle' for f in data['fixtures']),
        'building_types':sorted(set(f['asset'] for f in data['fixtures'] if f['kind']=='building')),
        'colliders':len(data['colliders']),'material_sections':len(materials),
        'ground_collision_unchanged':True,'elevator':data['elevator'],
        'foreground_sha256':hashlib.sha256((ASSETS/'foreground_native.png').read_bytes()).hexdigest()}
    (OUT/'layout_info.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report))

if __name__=='__main__': main()
