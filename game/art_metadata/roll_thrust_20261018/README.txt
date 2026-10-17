翻滚动画制作记录，2026-10-18
模式：内置 image_gen；透明背景。生成提示词见 prompt.txt，输入角色参考见 character_reference.png，原始生成图 generated_roll.png，原生导出总览 roll_atlas_native.png。
从同一张原画取16个姿势，统一缩放、沿用原18色，剔除洋红注册点，再对齐足点(56,84)。左向绕原生足点镜像。导入器 tools/art/import_roll.py 可复建32帧；QA tools/art_qa/validate_roll_art.py 会核对原1056帧不变、每向16姿势、颜色、透明和镜像。
动作保留36像素/0.30秒侧视翻滚（原0.22秒，现按用户要求放慢），地面与空中侧视均播放，朝向跟随移动方向。代码连续突刺改动与验证见 docs/verification/2026-10-18_roll-thrust.json。
