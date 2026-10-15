"""Generate the night-street prototype backdrop (2040 Petra new town, light = being watched).

Usage: python -I tools/art/gen_night_street.py
Writes game/assets/night_street/<layer>.png and <layer>_emit.png. The base layers are painted for a
CanvasModulate of about 0.5 (street lights reveal their true colours); the _emit layers hold only
self-lit pixels (windows, neon, beacons) and are drawn unshaded so they stay bright and bloom.
Deterministic: the same seed always produces the same pixels.
"""
import math
import random
from pathlib import Path

from PIL import Image

OUT = Path(__file__).resolve().parents[2] / "game" / "assets" / "night_street"
VIEW_W, VIEW_H = 320, 180
WORLD_W = 960
FLOOR = 156

BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

CYAN = (79, 240, 255)
MAGENTA = (255, 61, 154)
SODIUM = (255, 154, 60)
LAVENDER = (143, 160, 255)
RED = (255, 60, 70)


def hx(value: str) -> tuple[int, int, int]:
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


class Layer:
    def __init__(self, name: str, width: int):
        self.name = name
        self.base = Image.new("RGBA", (width, VIEW_H), (0, 0, 0, 0))
        self.emit = Image.new("RGBA", (width, VIEW_H), (0, 0, 0, 0))
        self.w = width

    def px(self, x, y, colour, alpha=255, emit=False):
        if 0 <= x < self.w and 0 <= y < VIEW_H:
            (self.emit if emit else self.base).putpixel((int(x), int(y)), tuple(colour) + (alpha,))

    def rect(self, x0, y0, x1, y1, colour, alpha=255, emit=False):
        for y in range(max(0, int(y0)), min(VIEW_H, int(y1) + 1)):
            for x in range(max(0, int(x0)), min(self.w, int(x1) + 1)):
                self.px(x, y, colour, alpha, emit)

    def hline(self, x0, x1, y, colour, alpha=255, emit=False):
        self.rect(x0, y, x1, y, colour, alpha, emit)

    def vline(self, x, y0, y1, colour, alpha=255, emit=False):
        self.rect(x, y0, x, y1, colour, alpha, emit)

    def neon_rect(self, x0, y0, x1, y1, colour):
        """Neon tube outline: lit tube in the emit layer, dark housing in the base layer."""
        self.rect(x0 - 1, y0 - 1, x1 + 1, y1 + 1, hx("0b0816"))
        for x in range(x0, x1 + 1):
            self.px(x, y0, colour, emit=True)
            self.px(x, y1, colour, emit=True)
        for y in range(y0, y1 + 1):
            self.px(x0, y, colour, emit=True)
            self.px(x1, y, colour, emit=True)

    def save(self):
        OUT.mkdir(parents=True, exist_ok=True)
        self.base.save(OUT / f"{self.name}.png")
        self.emit.save(OUT / f"{self.name}_emit.png")
        print("wrote", self.name, self.base.size)


def dithered_gradient(img_layer: Layer, stops, y0, y1, x0=0, x1=None):
    x1 = img_layer.w - 1 if x1 is None else x1
    for y in range(y0, y1 + 1):
        t = (y - y0) / max(1, y1 - y0)
        seg = min(len(stops) - 2, int(t * (len(stops) - 1)))
        local = t * (len(stops) - 1) - seg
        for x in range(x0, x1 + 1):
            threshold = (BAYER[y % 4][x % 4] + 0.5) / 16
            colour = stops[seg + 1] if local > threshold else stops[seg]
            img_layer.px(x, y, colour)


# ---------------------------------------------------------------- sky (fixed to the screen)
def sky():
    layer = Layer("sky", VIEW_W)
    stops = [hx("05041a"), hx("0a0824"), hx("140c33"), hx("26103f"), hx("421548"), hx("6a1f4e")]
    dithered_gradient(layer, stops, 0, FLOOR)
    rng = random.Random(3)
    # smog glow bands near the horizon, sodium + magenta
    for y in range(110, FLOOR):
        for x in range(VIEW_W):
            if rng.random() < 0.05 * (y - 110) / 46:
                layer.px(x, y, mix(hx("6a1f4e"), hx("8a3a55"), 0.6))
    # a handful of aircraft / satellite lights high up (emissive)
    for x, y, c in [(38, 14, RED), (171, 9, LAVENDER), (262, 21, CYAN), (300, 6, LAVENDER)]:
        layer.px(x, y, c, 200, emit=True)
    layer.rect(0, FLOOR, VIEW_W - 1, VIEW_H - 1, hx("0a0814"))
    layer.save()


# ---------------------------------------------------------------- far: A-district megatowers + regime spire
def far_towers():
    width = 448
    layer = Layer("far_towers", width)
    rng = random.Random(11)
    body, edge, dark = hx("161333"), hx("221c47"), hx("0f0c24")
    towers = [(4, 26, 92), (34, 18, 70), (56, 30, 104), (92, 16, 62), (114, 24, 86), (150, 34, 112),
              (262, 30, 118), (296, 18, 80), (318, 28, 100), (352, 20, 74), (376, 32, 108), (414, 26, 88)]
    for x0, w, h in towers:
        top = FLOOR - h
        layer.rect(x0, top, x0 + w, FLOOR, body)
        layer.vline(x0, top, FLOOR, edge)
        layer.rect(x0 + w - 2, top, x0 + w, FLOOR, dark)
        # setbacks and crowns
        if w > 22:
            layer.rect(x0 + 4, top - 6, x0 + w - 4, top, body)
            layer.vline(x0 + 4, top - 6, top, edge)
        if rng.random() < 0.6:
            layer.vline(x0 + w // 2, top - 14, top - 6, dark)
            layer.px(x0 + w // 2, top - 15, RED, emit=True)
        # window grid: sparse lit cells
        for wy in range(top + 4, FLOOR - 2, 3):
            for wx in range(x0 + 2, x0 + w - 2, 2):
                roll = rng.random()
                if roll < 0.10:
                    layer.px(wx, wy, CYAN, 150, emit=True)
                elif roll < 0.16:
                    layer.px(wx, wy, LAVENDER, 120, emit=True)
                elif roll < 0.18:
                    layer.px(wx, wy, SODIUM, 130, emit=True)
    # holo banner running down one tower
    for y in range(FLOOR - 104, FLOOR - 40, 2):
        if rng.random() < 0.8:
            layer.hline(158, 158 + rng.randint(1, 4), y, MAGENTA, 210, emit=True)
    # the regime spire (A-district control tower)
    cx = 210
    for y in range(4, FLOOR + 1):
        half = 2 if y < 40 else int(2 + (y - 40) * 0.11)
        layer.hline(cx - half, cx + half, y, hx("1c1840"))
        layer.px(cx - half, y, hx("2c2660"))
    for ring_y in (40, 70, 96):
        half = int(2 + (ring_y - 40) * 0.11) + 5
        layer.rect(cx - half, ring_y, cx + half, ring_y + 2, hx("241f52"))
        layer.hline(cx - half, cx + half, ring_y + 1, CYAN, 230, emit=True)
    layer.vline(cx, 6, 38, CYAN, 220, emit=True)
    layer.px(cx, 3, (255, 255, 255), emit=True)
    layer.px(cx, 4, CYAN, emit=True)
    layer.save()


# ---------------------------------------------------------------- mid: Petra rose-sandstone cliff and carved facade
def petra():
    width = 576
    layer = Layer("petra", width)
    rng = random.Random(23)
    base, light, shade, deep = hx("4a2038"), hx("62294a"), hx("361629"), hx("220c1a")
    # cliff contour
    top = []
    h = 44.0
    for x in range(width):
        h += rng.uniform(-2.2, 2.2) + (44 - h) * 0.03
        if rng.random() < 0.04:
            h += rng.choice([-6, 5, 7])
        top.append(int(h + 8 * math.sin(x / 41.0) + 3 * math.sin(x / 9.0)))
    for x in range(width):
        for y in range(top[x], FLOOR + 1):
            # swirled sandstone strata
            band = math.sin(y * 0.33 + math.sin(x * 0.031 + y * 0.02) * 2.4 + math.sin(x * 0.009) * 4.0)
            band += rng.uniform(-0.35, 0.35)
            colour = light if band > 0.95 else shade if band < -0.85 else base
            if (y - top[x]) > 70 and rng.random() < 0.25:
                colour = shade
            if y - top[x] < 2:
                colour = light
            layer.px(x, y, colour)
    # carved Khazneh-style facade
    fx, fw = 206, 124
    fy = 50
    layer.rect(fx, fy, fx + fw, FLOOR, shade)
    # lower order: six columns, pediment
    lower_top = fy + 50
    layer.rect(fx + 4, lower_top, fx + fw - 4, FLOOR, base)
    for i in range(6):
        cx = fx + 11 + i * 20
        layer.rect(cx, lower_top + 6, cx + 3, FLOOR - 2, light)
        layer.vline(cx + 3, lower_top + 6, FLOOR - 2, shade)
        layer.rect(cx - 1, lower_top + 4, cx + 4, lower_top + 5, light)
    layer.rect(fx + 2, lower_top, fx + fw - 2, lower_top + 3, light)
    for i in range(14):
        layer.hline(fx + 30 + i * 2, fx + fw - 30 - i * 2, lower_top - 1 - i, light if i % 3 else base)
    layer.rect(fx + 46, FLOOR - 26, fx + fw - 46, FLOOR, deep)   # doorway
    # upper order: tholos between broken pediments
    upper_y = fy
    layer.rect(fx + 8, upper_y + 10, fx + 30, lower_top - 14, base)
    layer.rect(fx + fw - 30, upper_y + 10, fx + fw - 8, lower_top - 14, base)
    for side in (fx + 8, fx + fw - 30):
        for i in range(8):
            layer.hline(side + i, side + 22 - i, upper_y + 9 - i, light)
        layer.rect(side + 4, upper_y + 14, side + 6, lower_top - 16, light)
        layer.rect(side + 16, upper_y + 14, side + 18, lower_top - 16, light)
    tx = fx + fw // 2
    layer.rect(tx - 12, upper_y + 4, tx + 12, lower_top - 14, base)
    for i in range(5):
        cx = tx - 10 + i * 5
        layer.rect(cx, upper_y + 8, cx + 1, lower_top - 16, light)
    for i in range(9):
        layer.hline(tx - 12 + i, tx + 12 - i, upper_y + 3 - i // 2, light)
    layer.rect(tx - 1, upper_y - 8, tx + 1, upper_y, light)  # urn
    # 2040 retrofit: neon trim on ancient stone, cables, cameras
    layer.hline(fx + 2, fx + fw - 2, lower_top + 1, MAGENTA, emit=True)
    for i in range(14):
        layer.px(fx + 30 + i * 2, lower_top - 1 - i, MAGENTA, 220, emit=True)
        layer.px(fx + fw - 30 - i * 2, lower_top - 1 - i, MAGENTA, 220, emit=True)
    layer.vline(tx - 13, upper_y + 4, lower_top - 14, CYAN, 200, emit=True)
    layer.vline(tx + 13, upper_y + 4, lower_top - 14, CYAN, 200, emit=True)
    layer.rect(fx + 46, FLOOR - 26, fx + fw - 46, FLOOR - 26, SODIUM, 200, emit=True)
    for cam_x, cam_y in [(fx - 14, 96), (fx + fw + 12, 90), (470, 84), (96, 92)]:
        layer.rect(cam_x, cam_y, cam_x + 4, cam_y + 2, hx("120a18"))
        layer.px(cam_x + 4, cam_y + 1, RED, emit=True)
    # second, smaller tomb front with a sodium lamp
    sx = 448
    layer.rect(sx, 104, sx + 40, FLOOR, shade)
    for i in range(4):
        layer.rect(sx + 4 + i * 10, 112, sx + 6 + i * 10, FLOOR - 2, base)
    for i in range(6):
        layer.hline(sx + 2 + i * 2, sx + 38 - i * 2, 106 - i, base)
    layer.rect(sx + 15, FLOOR - 18, sx + 25, FLOOR, deep)
    layer.rect(sx + 18, FLOOR - 22, sx + 22, FLOOR - 21, SODIUM, emit=True)
    # stairs cut into the rock, lit by a cyan strip
    for i in range(10):
        layer.hline(40 + i * 4, 52 + i * 4, 100 + i * 5, light)
        layer.px(52 + i * 4, 99 + i * 5, CYAN, 160, emit=True)
    layer.save()


# ---------------------------------------------------------------- near: C-district blocks, balconies, signs
def district_c():
    width = 768
    layer = Layer("district_c", width)
    rng = random.Random(37)
    wall, edge, dark = hx("231b3e"), hx("33295a"), hx("16112a")
    x = 0
    blocks = []
    while x < width:
        tall = rng.random() < 0.18
        w = rng.randint(20, 28) if tall else rng.randint(36, 64)
        top = rng.randint(78, 94) if tall else rng.randint(106, 128)
        blocks.append((x, w, top))
        x += w + rng.choice([0, 0, 2, 4, 18, 30])
    for x0, w, top in blocks:
        layer.rect(x0, top, x0 + w, FLOOR, wall)
        layer.vline(x0, top, FLOOR, edge)
        layer.rect(x0 + w - 1, top, x0 + w, FLOOR, dark)
        layer.hline(x0, x0 + w, top, edge)
        # roof clutter
        if rng.random() < 0.7:
            tx = x0 + rng.randint(4, max(5, w - 14))
            layer.rect(tx, top - 8, tx + 9, top - 1, dark)
            layer.vline(tx + 2, top - 12, top - 8, dark)
        if rng.random() < 0.5:
            ax = x0 + rng.randint(2, w - 2)
            layer.vline(ax, top - 18, top, dark)
            layer.px(ax, top - 19, RED, emit=True)
        # floors with windows and balconies
        for fy in range(top + 5, FLOOR - 12, 8):
            for wx in range(x0 + 3, x0 + w - 4, 5):
                layer.rect(wx, fy, wx + 1, fy + 2, dark)
                roll = rng.random()
                if roll < 0.11:
                    layer.rect(wx, fy, wx + 1, fy + 2, SODIUM, 140, emit=True)
                elif roll < 0.14:
                    layer.rect(wx, fy, wx + 1, fy + 2, MAGENTA, 120, emit=True)
                elif roll < 0.17:
                    layer.rect(wx, fy, wx + 1, fy + 2, CYAN, 110, emit=True)
            if rng.random() < 0.35:
                layer.hline(x0 + 2, x0 + w - 2, fy + 6, edge)
            if rng.random() < 0.25:
                ux = x0 + rng.randint(2, w - 8)
                layer.rect(ux, fy + 5, ux + 5, fy + 8, hx("3b3260"))   # AC unit
        # vertical glyph sign
        if rng.random() < 0.5 and w > 40:
            sx = x0 + w - 8
            sy = top - rng.randint(2, 14)
            colour = rng.choice([MAGENTA, CYAN, SODIUM, MAGENTA])
            layer.neon_rect(sx, sy, sx + 5, sy + 26, colour)
            for gy in range(sy + 3, sy + 24, 4):
                layer.hline(sx + 2, sx + 2 + rng.randint(0, 2), gy, colour, 220, emit=True)
    # cables across the blocks
    for _ in range(9):
        a = rng.randint(0, width - 120)
        b = a + rng.randint(80, 200)
        y0 = rng.randint(96, 116)
        sag = rng.randint(4, 12)
        for xx in range(a, min(b, width)):
            yy = y0 + int(sag * math.sin(math.pi * (xx - a) / (b - a)))
            layer.px(xx, yy, hx("0b0816"))
    layer.save()


# ---------------------------------------------------------------- street level (scroll 1.0): props and wet asphalt
def street():
    layer = Layer("street", WORLD_W)
    rng = random.Random(41)
    # sidewalk wall at the back of the street
    layer.rect(0, FLOOR - 10, WORLD_W - 1, FLOOR - 1, hx("1a142e"))
    layer.hline(0, WORLD_W - 1, FLOOR - 10, hx("2d2450"))
    for x in range(0, WORLD_W, 24):
        layer.vline(x, FLOOR - 9, FLOOR - 1, hx("120e22"))
    # asphalt
    for y in range(FLOOR, VIEW_H):
        for x in range(WORLD_W):
            layer.px(x, y, hx("0d0b1a") if (x * 7 + y * 13) % 11 else hx("110e20"))
    layer.hline(0, WORLD_W - 1, FLOOR, hx("3e3266"))
    for x in range(0, WORLD_W, 40):
        layer.hline(x + 6, x + 22, FLOOR + 12, hx("2a2346"))
    # street lamps (sodium) - the light itself is a PointLight2D placed by the scene
    for lx in (120, 430, 780):
        layer.vline(lx, 96, FLOOR - 1, hx("2a2244"))
        layer.vline(lx + 1, 96, FLOOR - 1, hx("1a1530"))
        layer.hline(lx - 8, lx + 1, 96, hx("2a2244"))
        layer.rect(lx - 11, 96, lx - 6, 98, hx("3a2f58"))
        layer.hline(lx - 10, lx - 7, 99, SODIUM, emit=True)
        layer.rect(lx - 2, FLOOR - 4, lx + 3, FLOOR - 1, hx("2a2244"))
    # noodle kiosk with magenta sign
    kx = 236
    layer.rect(kx, 118, kx + 46, FLOOR - 1, hx("241b3c"))
    layer.rect(kx + 3, 128, kx + 43, FLOOR - 14, hx("120d20"))
    layer.rect(kx + 3, 128, kx + 43, FLOOR - 14, SODIUM, 70, emit=True)
    layer.rect(kx - 2, 124, kx + 48, 127, hx("3a2f58"))
    for i in range(0, 50, 4):
        layer.rect(kx - 2 + i, 124, kx + i, 127, MAGENTA, 160, emit=True)
    layer.neon_rect(kx + 8, 106, kx + 38, 116, MAGENTA)
    for gx in range(kx + 12, kx + 35, 5):
        layer.vline(gx, 109, 113, (255, 140, 200), emit=True)
        layer.hline(gx, gx + 2, 111, (255, 140, 200), emit=True)
    # vending machine (cyan)
    vx = 560
    layer.rect(vx, 120, vx + 16, FLOOR - 1, hx("1d2a44"))
    layer.rect(vx + 2, 123, vx + 14, 140, CYAN, 120, emit=True)
    for gy in range(125, 139, 3):
        layer.hline(vx + 3, vx + 13, gy, (190, 255, 255), 160, emit=True)
    layer.rect(vx + 3, 144, vx + 7, 146, MAGENTA, emit=True)
    # holo ID gate (barcode) near the far end
    gx = 690
    layer.rect(gx, 112, gx + 3, FLOOR - 1, hx("2a2244"))
    layer.rect(gx + 30, 112, gx + 33, FLOOR - 1, hx("2a2244"))
    layer.hline(gx, gx + 33, 112, hx("2a2244"))
    for bx in range(gx + 6, gx + 28):
        if rng.random() < 0.55:
            layer.vline(bx, 115, 121, CYAN, 200, emit=True)
    # crates, bins, barrier
    for bx, bw, bh in [(30, 14, 10), (46, 10, 7), (330, 16, 12), (620, 12, 9), (880, 18, 11)]:
        layer.rect(bx, FLOOR - bh, bx + bw, FLOOR - 1, hx("2a2140"))
        layer.hline(bx, bx + bw, FLOOR - bh, hx("3e3266"))
    # power cables at street level
    for a, b, y0, sag in [(0, 240, 84, 8), (240, 560, 80, 10), (560, 960, 86, 7)]:
        for xx in range(a, b):
            layer.px(xx, y0 + int(sag * math.sin(math.pi * (xx - a) / (b - a))), hx("0b0816"))
    layer.save()


if __name__ == "__main__":
    sky()
    far_towers()
    petra()
    district_c()
    street()
