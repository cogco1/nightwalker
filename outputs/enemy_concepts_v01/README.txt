夜行者 - 工业封锁守卫概念设定集 v0.1
日期：2026-10-21

本轮交付为静态造型与战斗设计提案，未向游戏安装敌人 AI、碰撞、攻击逻辑或正式剧情。
所有人形单位配备工业外骨骼；激光 AI 浮游炮为独立无人单位。
代号、呼号与身份暂拟，不作为 SK 剧本正史。

兵种索引
NW-E01 烛眼 - 激光 AI 浮游炮
NW-E02 长哨 - 轻型外骨骼狙击兵
NW-E03 铁巡 - 标准外骨骼步枪兵
NW-E04 门闩 - 重型外骨骼盾卫
NW-E05 折刃 - 腿部助力外骨骼刀刃突击兵
NW-E06 碎砧 - 厚支撑外骨骼重锤破甲兵
NW-E07 牵线 - 轻中型外骨骼磁索牵制兵

每个兵种有 A / B / C 三个静态造型方向，共 21 个。它们不是动画连续帧。
原生图位于 asset_images，每类为 192×64 透明 PNG，由 3 个 64×64 单元组成。
本轮人形样张的可见轮廓均为 32 原生像素高，浮游炮均为 28 原生像素宽。
规范建议成人站高 28-32 像素；不通过放大角色表现重装。
preview_images 是最近邻放大查看图，原生素材应使用最近邻、scale=1。

夜行者_敌人概念设定集_v01.pdf：完整可检索中文设定集，包含造型、代号、外骨骼、武器、
行为提案、攻击前兆、弱点、建议动画、组合与后续制作步骤。
enemy_designs.json：相同设定文案的结构化版本。
generation_prompts.json：原画生成提示词和来源。
source_art：生成器输出的原始画稿。
asset_images：按游戏原生像素网格规范化的透明素材。
preview_images：放大预览。
book_preview：PDF 全页渲染与总览，供视觉验收。
book_validation.json：PDF 页数与中文检索验证记录。

PDF 重建
使用含 ReportLab、Pillow、pypdf 的 Python：
python tools/build_enemy_concept_book.py --render
工具默认从当前仓库 outputs/enemy_concepts_v01 读取素材与文案。
完整渲染需要 Poppler pdftoppm；默认路径是当前机器的 Codex bundled runtime。
更换机器时可调整脚本顶部 FONT_PATH 与 POPPLER。

美术生成：Codex 内置 image_gen；具体提示词与单次来源见 generation_prompts.json。
像素规范化、透明阈值、配色和最近邻预览步骤由本轮构建脚本记录。
