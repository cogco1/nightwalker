"""Native body comparisons; padding and weapons do not define actor size."""
from pathlib import Path
import json
from PIL import Image, ImageDraw

PROJECT = Path(__file__).resolve().parents[2] / "game"
ART = PROJECT.parent / "art" / "characters" / "animation_v06"
EVIDENCE = PROJECT / "evidence"
SELECTED = [0,2,4,6,8,10,12,15]
REGISTERED = json.loads((ART / "export_report.json").read_text(encoding="utf-8"))["clips"]

def body_crop(path):
    image = Image.open(path).convert("RGBA")
    pivot = (image.width // 2, image.height - 12) if image.height >= 64 else (24,42)
    return image.crop((pivot[0]-16,pivot[1]-32,pivot[0]+16,pivot[1]+2))

def review(view, direction, actions):
    width, height = 128, 136
    label_height = 24
    canvas = Image.new("RGB",(8*(width+4),len(actions)*(height+label_height+4)),(18,22,29))
    draw = ImageDraw.Draw(canvas)
    for row, action in enumerate(actions):
        for column, index in enumerate(SELECTED):
            path = PROJECT / "frames" / f"{view}_{direction}_{action}" / f"{index:02}.png"
            x, y = column*(width+4), row*(height+label_height+4)
            if f"{view}_{direction}_{action}" not in REGISTERED:
                draw.text((x+3,y+4),f"{action}: NEW ATLAS PENDING",fill=(210,150,115))
                continue
            native = body_crop(path).resize((width,height),Image.Resampling.NEAREST)
            canvas.paste(native,(x,y+label_height),native)
            draw.text((x+3,y+4),f"{action} frame {index:02}",fill=(220,230,239))
            # Same foot-pivot row in every cell, independent of canvas padding.
            draw.line((x,y+label_height+32*4,x+width-1,y+label_height+32*4),fill=(51,66,78))
    destination = EVIDENCE / f"{view}_{direction}_{'combo' if actions[0] == 'idle' else 'movement'}_body_proportions_review.png"
    canvas.save(destination)
    print(destination)

if __name__ == "__main__":
    EVIDENCE.mkdir(exist_ok=True)
    for view,direction in [("side_view","right"),("top_down","down"),("top_down","up")]:
        review(view,direction,["idle","attack1","attack2","attack3"])
    review("side_view","right",["walk","run","jump","crouch","crouch_stab"])
