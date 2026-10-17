侧视右键重击，2026-10-18。
通过内置 image_gen 生成独立16姿势，用原右侧攻击atlas作为角色/风格参考；完整提示词见generation_prompt.txt，生成原图见generated_heavy_cleave.png。没有使用外部美术素材。
导入脚本tools/art/import_heavy_cleave.py：单一全局比例缩小、18色量化、统一足点；左右镜像围绕原生x=56，画布112×96。每帧单独绘制，不旋转整个人物或拉伸肢体。原1088张PNG原字节保留，新增32帧；新刀尖轨迹写入assets/blade_paths.json。
重建：python tools/art/import_heavy_cleave.py。时序和注册记录见import.json，原生核对图native_review.png。
右键蓄势约0.36秒，3倍伤害、加强击退、10帧卡肉。无额外无敌/霸体，挥空有0.16秒恢复；普攻轻顿帧为2帧。详见操作说明和ARCHITECTURE。
