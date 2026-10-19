"""Place generated walkable modules and serialize their painted collision surfaces."""
from pathlib import Path
import hashlib
import json
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'outputs/battlefield_traversal_v06'
ASSETS = ROOT / 'game/assets/battlefield_traversal'
ORIGIN = (0,-256)
SIZE = (6144,512)
GROUND = 168

# Each top follows an exposed painted floor lip, not a handrail above the deck.
DECKS = {
    'gatehouse': [('left_landing',[0,185,48,5]),('second_floor',[57,187,161,5]),
                  ('right_landing',[223,200,33,5]),('roof',[30,143,202,5])],
    'tower': [('left_landing',[0,178,49,5]),('right_landing',[214,192,42,5]),
              ('second_floor',[54,126,201,5]),('upper_landing',[0,80,39,5]),
              ('roof',[55,46,153,5]),('roof_right',[208,48,48,5])]
}
STAIRS = [
    ('lower_left',[(38,178),(69,126),(69,132),(38,184)]),
    ('upper_left',[(37,80),(68,126),(68,132),(37,86)]),
    ('roof_left',[(37,80),(58,46),(58,52),(37,86)]),
    ('lower_right',[(196,126),(238,192),(238,198),(196,132)])
]
PLACEMENTS = [
    ('gate_01','gatehouse',640),('tower_01','tower',912),
    ('gate_02','gatehouse',1376),('tower_02','tower',3200),('gate_03','gatehouse',4800),
    ('sedan_01','wreck_sedan',560),('van_01','wreck_van',912),
    ('truck_01','wreck_truck',1240),('sedan_02','wreck_sedan',1792),
    ('van_02','wreck_van',3104),('truck_02','wreck_truck',3520),('sedan_03','wreck_sedan',4720)
]


def main():
    canvas = Image.new('RGBA', SIZE)
    colliders, fixtures = [], []
    for identity, name, x in PLACEMENTS:
        art = Image.open(ASSETS / (name+'.png')).convert('RGBA')
        y = GROUND - art.height
        canvas.alpha_composite(art,(x,y-ORIGIN[1]))
        fixture = {'id':identity,'asset':name+'.png','kind':'building' if name in DECKS else 'vehicle',
                   'position':[x,y],'rect':[x,y,art.width,art.height],'surfaces':[]}
        if name in DECKS:
            for surface, local in DECKS[name]:
                sid = identity+'_'+surface
                lx,ly,w,h = local
                colliders.append({'id':sid,'rect':[x+lx,y+ly,w,h],'one_way':True,
                                  'kind':'roof' if surface.startswith('roof') else 'floor','fixture_id':identity})
                fixture['surfaces'].append(sid)
            if name == 'tower':
                for surface, points in STAIRS:
                    sid = identity+'_stairs_'+surface
                    colliders.append({'id':sid,'polygon':[[x+px,y+py] for px,py in points],
                                      'one_way':True,'kind':'stairs','fixture_id':identity})
                    fixture['surfaces'].append(sid)
        else:
            alpha = np.array(art.getchannel('A'))
            xs = list(range(2,art.width-2,4))+[art.width-3]
            top = [[px,int(np.flatnonzero(alpha[:,px]>0)[0])+1] for px in xs]
            polygon = top+[[art.width-3,art.height],[2,art.height]]
            sid = identity+'_body'
            colliders.append({'id':sid,'polygon':[[x+px,y+py] for px,py in polygon],
                              'top_profile':[[x+px,y+py] for px,py in top],
                              'one_way':False,'kind':'vehicle','fixture_id':identity})
            fixture['surfaces'].append(sid)
            fixture['body_id'] = sid
        fixtures.append(fixture)
    def point(identity, surface, x, y, mode='jump'):
        return {'id':identity,'surface_id':surface,'position':[x,y],'mode':mode}
    waypoints = [
        point('sedan_roof','sedan_01_body',612,147),
        point('gate_left_landing','gate_01_left_landing',664,97),
        point('gate_second_floor','gate_01_second_floor',720,99,'walk'),
        point('gate_roof','gate_01_roof',760,55),
        point('gate_roof_edge','gate_01_roof',862,55,'walk'),
        point('tower_low_landing','tower_01_left_landing',934,90),
        point('tower_second_floor','tower_01_second_floor',990,38,'walk'),
        point('tower_upper_landing','tower_01_upper_landing',932,-8,'walk'),
        point('tower_roof','tower_01_roof',1008,-42,'walk'),
        point('tower_roof_edge','tower_01_roof',1104,-42,'walk'),
        point('return_to_sand','ground',1218,168,'walk'),
        point('truck_cab','truck_01_body',1274,134),
        point('truck_flatbed','truck_01_body',1324,150,'walk'),
        point('route_exit','ground',1408,168,'walk')
    ]
    data = {'version':6,'origin':list(ORIGIN),'art_size':list(SIZE),
            'ground_unchanged':True,'route_start':[530,168],
            'fixtures':fixtures,'colliders':colliders,'waypoints':waypoints}
    OUT.mkdir(parents=True,exist_ok=True)
    canvas.save(ASSETS / 'foreground_native.png',optimize=True)
    canvas.save(OUT / 'foreground_native.png',optimize=True)
    canvas.resize((12288,1024),Image.Resampling.NEAREST).save(OUT / 'foreground_12288x1024.png',optimize=True)
    encoded = json.dumps(data,ensure_ascii=False,indent=2)+'\n'
    for path in (ASSETS/'layout.json',OUT/'layout.json'):
        with path.open('w',encoding='utf-8',newline='\n') as stream: stream.write(encoded)
    report = {'foreground_size':list(SIZE),'origin':list(ORIGIN),
              'fixtures':len(fixtures),'buildings':5,'vehicles':7,
              'colliders':len(colliders),'waypoints':len(waypoints),
              'foreground_sha256':hashlib.sha256((ASSETS/'foreground_native.png').read_bytes()).hexdigest(),
              'source_art':'built-in-imagegen','composition':'user-authorized pixel alignment and placement'}
    (OUT/'layout_info.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
