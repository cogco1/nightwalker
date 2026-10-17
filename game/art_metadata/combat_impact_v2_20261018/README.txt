打击感 v2，2026-10-18
视觉由原生代码绘制，不引入新人物帧图；1088张PNG保持原字节。impact_v2.gd 绘制短促普通混合弯月刀光、材质飞溅与击杀断环，不使用大面积加法白填充。timing.json保存24组动作的时长参数。
音效由tools/audio/gen_impact_sfx_v2.py确定性合成（NumPy和Python标准wave），新6段存入assets/audio/sfx/impact_v2；原11段音频保留。audio.json记录格式、时长与电平。
突刺 hit_feedback=false，保留伤害、穿透与物理反应；legacy_dash_hit_feedback.gd保留旧VFX入口、原hit_light音频和impact_frame着色器引用。legacy/中完整存档4份改前源码。新版player_fx仍可调用legacy_impact。
校验tools/art_qa/validate_combat_impact_v2.py；逻辑tests/test_combat_impact_v2.gd；录制tests/recorders/record_combat_impact_v2.gd。录制器只在自己的实例中控制AI与摆放测试目标，不改正式关卡。验证见docs/verification/2026-10-18_combat-impact-v2.json。
