蓄力拔刀斩加强，2026-10-18。
通过内置image_gen生成16姿势，用上一版重击和原长刀atlas作为角色/色板/武器参考；完整提示词generation_prompt.txt，原图generated_charged_draw.png。借鉴不死斩的蓄势反差和黑红斩痕，原角色与素材形象由本工程继续创作，没有使用只狼的游戏素材。
tools/art/import_charged_draw.py按透明连通主体提取整个人物与刀刃，以同一比例缩小、18色量化和足点56/84对齐；112×96画布，左右镜像。0–6用于蓄势，释放从6衔接到15。导入时长与注册数据见import.json，核对native_review.png。原1120帧不改，新增32帧。
黑红刀气在scripts/player/charged_draw.gd原生绘制，普通混合、0.14秒，上限2道，墙体缩短效果。6倍伤害、120×56侧视判定，保留打断和收招；详见操作说明及ARCHITECTURE。
官方概念参考：https://support.activision.com/sekiro/articles/sekiro-shadows-die-twice-game-mechanics
