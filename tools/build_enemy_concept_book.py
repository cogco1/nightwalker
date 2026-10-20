"""Build the enemy concept PDF from approved native art and design JSON.

Requires the Codex bundled Python (ReportLab, Pillow, pypdf) and Poppler.
The book is a design proposal; it does not install enemy AI into the game.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess

from PIL import Image, ImageDraw, ImageFont
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor
from reportlab.lib.utils import ImageReader
from pypdf import PdfReader


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "outputs/enemy_concepts_v01"
PDF = OUT / "夜行者_敌人概念设定集_v01.pdf"
FONT_PATH = Path("C:/Windows/Fonts/simhei.ttf")
POPPLER = Path("C:/Users/31459/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/poppler/Library/bin")
W, H = 1080, 764
M = 44
BG = "#151C20"
PANEL = "#1D272C"
LINE = "#344249"
TEXT = "#E4E0D4"
MUTED = "#9CA9A8"
ACCENT = "#D8A157"
TEAL = "#7BA9AC"
FONT = "EnemyHei"


def clean_text(value):
    return str(value).translate(str.maketrans({"\u2011": "-", "\u2013": "-", "\u2014": "-"}))


class Book:
    def __init__(self, data):
        pdfmetrics.registerFont(TTFont(FONT, str(FONT_PATH)))
        self.c = canvas.Canvas(str(PDF), pagesize=(W, H), pageCompression=1)
        self.c.setTitle(data["title"])
        self.c.setAuthor("Nightwalker / cogco1")
        self.c.setSubject("外骨骼守卫与激光 AI 浮游炮 - 像素概念初稿")
        self.data = data
        self.page = 0
        self.errors = []
        self.text_boxes = []

    def rect(self, x, y, w, h, color, stroke=None):
        self.c.setFillColor(HexColor(color))
        self.c.setStrokeColor(HexColor(stroke or color))
        self.c.rect(x, H - y - h, w, h, fill=1, stroke=int(stroke is not None))

    def text(self, x, y, value, size=12, color=TEXT):
        self.c.setFont(FONT, size)
        self.c.setFillColor(HexColor(color))
        self.c.drawString(x, H - y - size, clean_text(value))

    def rule(self, x, y, w, color=LINE):
        self.rect(x, y, w, 0.8, color)

    def wrap(self, value, width, size):
        # CJK with Latin tokens; punctuation must not start a fresh line.
        lines, current = [], ""
        for char in clean_text(value):
            if char == "\n":
                lines.append(current)
                current = ""
                continue
            candidate = current + char
            if current and pdfmetrics.stringWidth(candidate, FONT, size) > width:
                if char in "，。、；：！？）》】」』":
                    lines.append(candidate)
                    current = ""
                else:
                    lines.append(current.rstrip())
                    current = char.lstrip()
            else:
                current = candidate
        if current:
            lines.append(current)
        return lines

    def para(self, x, y, width, value, size=11.5, leading=17, color=TEXT, max_y=710):
        lines = self.wrap(value, width, size)
        end = y + len(lines) * leading
        self.text_boxes.append({"page": self.page, "x": x, "y": y, "bottom": end, "lines": len(lines)})
        if end > max_y:
            self.errors.append(f"Page {self.page}: paragraph ends at {end:.1f} > {max_y}")
        for i, line in enumerate(lines):
            self.text(x, y + i * leading, line, size, color)
        return end

    def block(self, x, y, width, heading, body, size=11, leading=16):
        self.text(x, y, heading, 10, ACCENT)
        y = self.para(x, y + 17, width, body, size=size, leading=leading)
        return y + 12

    def page_start(self, section, title, subtitle=""):
        self.page += 1
        self.rect(0, 0, W, H, BG)
        self.rect(M, 29, 5, 16, ACCENT)
        self.text(M + 15, 30, "NIGHTWALKER  /  ENEMY FIELD ARCHIVE", 10, MUTED)
        self.text(W - M - 153, 30, section, 10, MUTED)
        self.rule(M, 57, W - 2 * M)
        self.text(M, 77, title, 28)
        if subtitle:
            self.text(M + 1, 117, subtitle, 11, MUTED)
        self.rule(M, H - 36, W - 2 * M)
        self.text(M, H - 27, "概念初稿 v0.1  |  美术与战斗提案  |  未接入敌人 AI", 8.5, MUTED)
        self.text(W - M - 82, H - 27, f"{self.page:02d} / 11", 8.5, ACCENT)

    def page_end(self):
        self.c.showPage()

    def sprite(self, key, variant, x, y, scale=3):
        native = Image.open(OUT / "asset_images" / f"{key}_native.png").convert("RGBA")
        if native.size != (192, 64):
            raise ValueError(f"Bad native dimensions: {key}: {native.size}")
        frame = native.crop((variant * 64, 0, (variant + 1) * 64, 64))
        # Integer enlargement before PDF embedding makes the pixel grid explicit.
        img = frame.resize((64 * scale, 64 * scale), Image.Resampling.NEAREST)
        self.c.drawImage(ImageReader(img), x, H - y - img.height, width=img.width, height=img.height, mask="auto")

    def cover(self):
        self.page_start("ARCHIVE 01", "夜行者 / 工业封锁守卫设定集", "7 个兵种 · 21 个造型方向 · 统一原生像素网格")
        keys = self.data["order"]
        gap, tile = 10, 132
        start = M
        for i, key in enumerate(keys):
            x = start + i * (tile + gap)
            self.rect(x, 168, tile, 225, PANEL)
            self.sprite(key, 0, x + 2, 192, 2)
            enemy = self.data["classes"][key]
            self.text(x + 13, 335, enemy["code"], 10, ACCENT)
            self.text(x + 13, 357, enemy["callsign"], 19)
        self.para(M, 435, 650, self.data["shared_direction"]["setting"], 17, 27)
        self.para(M, 528, 650, "人形单位统一配备工业外骨骼。通过装甲结构、工具与战斗姿态区分职能，保留工作服、关节和承力架之间的空隙。", 13, 22)
        self.rect(794, 435, 242, 163, PANEL)
        self.text(812, 453, "当前阶段", 11, ACCENT)
        self.para(812, 479, 204, "用于选型与后续动画制作。\n代号与身份暂拟。\n行为、预兆与弱点均待实现。\n不作为 SK 剧本正史。", 11.5, 23)
        self.text(M, 674, "VERSION 0.1    /    2026-10-21", 11, ACCENT)
        self.page_end()

    def standards(self):
        self.page_start("DESIGN RULES", "统一美术规范", "以剪影、装备和外骨骼承力结构辨认兵种")
        rules = self.data["shared_direction"]
        left_x, right_x, col = M, 566, 470
        y = 160
        for heading, key in [("01  身高与像素", "pixel_grid"), ("02  本轮样张", "sample_note"), ("03  配色与识别", "palette"), ("04  变体边界", "readability")]:
            y = self.block(left_x, y, col, heading, rules[key], 13, 22)
        y = 160
        for heading, text in [("05  共用装备语言", "头盔与面罩控制在紧凑尺度；肩背承力框架连接肘、髋与膝。装甲分片之间露出工作服，脚部保留可辨认的落脚点。浮游炮作为独立无人单位，不套人形外骨骼。"), ("06  画面与制作", "本册均为纯侧视的静态造型提案，三个版本为 A / B / C，不是连续动画。原生素材每类 192×64 像素，由 3 个 64×64 单元组成；本轮人形轮廓在单元内以 32 像素高度绘制。"), ("07  战斗范围", rules["combat_scope"]), ("08  调参与落地", rules["tuning_note"])]:
            y = self.block(right_x, y, col, heading, text, 12, 20)
        self.rect(M, 649, W - 2 * M, 52, PANEL)
        self.text(M + 16, 662, "识别优先级", 11, ACCENT)
        self.text(M + 118, 662, "武器轮廓  >  外骨骼结构  >  姿态重心  >  小面积识别灯", 13)
        self.page_end()

    def enemy(self, key):
        enemy = self.data["classes"][key]
        self.page_start(enemy["code"], f"{enemy['callsign']} / {enemy['name']}", enemy["role"])
        slot_w = 320
        for i in range(3):
            x = M + i * 336
            self.rect(x, 156, slot_w, 232, PANEL)
            self.text(x + 14, 167, f"VARIANT {chr(65 + i)}", 10, ACCENT)
            self.sprite(key, i, x + 32, 108, 4)
            desc = re.sub(r"^[ABC]：", "", enemy["variant_notes"][i])
            self.para(x + 14, 343, slot_w - 28, desc, 9.5, 14, MUTED, max_y=390)
        left_x, right_x, col = M, 558, 478
        y = 404
        for heading, field in [("剪影与尺度", "silhouette"), ("外骨骼与装甲", "armor"), ("武器与行动", "weapon")]:
            y = self.block(left_x, y, col, heading, enemy[field], 11, 16)
        y = self.block(left_x, y, col, "行为提案", enemy["behavior"], 11, 16)
        y = 404
        for heading, field in [("攻击前兆", "telegraph"), ("应对与弱点", "weakness"), ("适合的场地", "environment")]:
            y = self.block(right_x, y, col, heading, enemy[field], 11, 16)
        animations = " / ".join(enemy["animation_priority"])
        self.block(right_x, y, col, "建议动画清单", animations, 10, 15)
        self.page_end()

    def encounters(self):
        self.page_start("ENCOUNTER DESIGN", "组合与出现顺序", "先让玩家读懂一种意图，再叠加第二种压力")
        cards = [
            ("01 / 沙地巡逻", "铁巡 + 折刃", "用废车与低楼切开视线。步枪兵先举枪，突击兵稍后蓄腿；避免两者在同一瞬间无前兆攻击。", "检查：玩家能否看清抬枪与压腿两个不同动作。"),
            ("02 / 双层厂房", "长哨 + 烛眼", "狙击兵驻守高层，浮游炮巡航于另一高度。通过二楼、车顶和实体遮挡提供换线机会，射线不得隔墙。", "检查：每个瞄准点附近都有能离开射界的路径。"),
            ("03 / 门厅绕行", "门闩 + 牵线", "盾卫守正面，磁索兵占据侧向中距离。上方平台允许跨过盾卫；柱体与车体能够阻断索线。", "检查：唯一出入口与电梯落脚处保持可通过。"),
            ("04 / 大厂房重击", "碎砧 + 铁巡", "破甲兵负责底层重击，步枪兵守在可绕到的短平台。重锤前兆拉长，举锤与点射错开出现。", "检查：砸击区前后都有可见的撤离空间。"),
        ]
        for i, (title, pair, desc, note) in enumerate(cards):
            x = M + (i % 2) * 514
            y = 163 + (i // 2) * 250
            self.rect(x, y, 478, 226, PANEL)
            self.text(x + 20, y + 18, title, 11, ACCENT)
            self.text(x + 20, y + 48, pair, 22)
            self.para(x + 20, y + 92, 438, desc, 12.5, 21)
            self.para(x + 20, y + 175, 438, note, 10.5, 17, TEAL)
        self.page_end()

    def production(self):
        self.page_start("PRODUCTION HANDOFF", "后续制作与交付索引", "先选造型，再做动作；本轮保持概念提案边界")
        y = 164
        stages = [
            ("1 / 造型确认", "每类从 A / B / C 中选择基础方案。用同一侧视相机，把七类兵种与现有主角并排，确认身高、武器长度及远距离辨识。"),
            ("2 / 动画打样", "优先做待机、行走或悬浮、攻击前兆、攻击、收招、受击、死亡。近战先验证压腿、定脚与回收，远程先验证锁线与后坐节奏。"),
            ("3 / 单兵原型", "每次只接入一个兵种，先验证实体地形遮挡、楼层边界与转向。行为与数字均重新试玩调整，不将概念说明直接当成既定战斗参数。"),
            ("4 / 组合验证", "单兵读招稳定后再组合，错开攻击节奏。验证现有突刺、上挑、空中三连击与下劈能否自然形成应对，保留撤离与接近路线。"),
        ]
        for title, desc in stages:
            y = self.block(M, y, 478, title, desc, 12, 20)
        x = 558
        self.rect(x, 164, 478, 390, PANEL)
        self.text(x + 20, 184, "资源文件", 13, ACCENT)
        self.para(x + 20, 222, 438, "asset_images/*_native.png\n7 张透明原生像素图；每张 3 个造型。\n\npreview_images/*_preview.png\n最近邻放大的查看版本。\n\nenemy_designs.json\n7 个兵种的完整中文文案与代号。\n\ngeneration_prompts.json\n本轮原画生成提示词与来源。", 12, 22)
        self.block(x, 584, 478, "当前交付状态", "已完成静态概念与设定集；未新增游戏敌人、AI、碰撞、伤害或正式剧情内容。", 12.5, 21)
        self.page_end()

    def save(self):
        if self.page != 11:
            self.errors.append(f"Expected 11 pages, got {self.page}")
        if self.errors:
            raise ValueError("\n".join(self.errors))
        self.c.save()


def render_and_validate():
    preview_dir = OUT / "book_preview"
    preview_dir.mkdir(exist_ok=True)
    command = [str(POPPLER / "pdftoppm.exe"), "-r", "100", "-png", str(PDF), str(preview_dir / "page")]
    result = subprocess.run(command, capture_output=True, timeout=180)
    if result.returncode:
        raise RuntimeError(result.stderr.decode("utf-8", "replace"))
    pages = sorted(preview_dir.glob("page-*.png"))
    reader = PdfReader(str(PDF))
    text = "\n".join(page.extract_text() or "" for page in reader.pages)
    if len(pages) != 11 or len(reader.pages) != 11:
        raise ValueError("Expected 11 PDF and preview pages")
    if "外骨骼" not in text or "NW-E07" not in text or "未接入" not in text:
        raise ValueError("Chinese searchable text QA failed")
    thumb_w = 432
    thumb_h = round(thumb_w * H / W)
    contact = Image.new("RGB", (thumb_w * 3, (thumb_h + 26) * 4), BG)
    draw = ImageDraw.Draw(contact)
    font = ImageFont.truetype(str(FONT_PATH), 15)
    for i, path in enumerate(pages):
        img = Image.open(path).convert("RGB").resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
        x, y = (i % 3) * thumb_w, (i // 3) * (thumb_h + 26)
        contact.paste(img, (x, y))
        draw.text((x + 12, y + thumb_h + 4), f"{i+1:02d}", font=font, fill=TEXT)
    contact.save(preview_dir / "contact_sheet.png")
    summary = {"pdf": str(PDF), "pages": len(reader.pages), "rendered_pngs": len(pages), "searchable_chinese": True, "text_characters": len(text), "poppler_returncode": result.returncode, "visual_review_required": True}
    (OUT / "book_validation.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return summary


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--render", action="store_true")
    args = parser.parse_args()
    data = json.loads((OUT / "enemy_designs.json").read_text(encoding="utf-8"))
    book = Book(data)
    book.cover()
    book.standards()
    for key in data["order"]:
        book.enemy(key)
    book.encounters()
    book.production()
    book.save()
    if args.render:
        print(json.dumps(render_and_validate(), ensure_ascii=False, indent=2))
    else:
        print(PDF)


if __name__ == "__main__":
    main()
