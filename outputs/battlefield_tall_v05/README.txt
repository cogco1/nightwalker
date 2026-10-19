夜行者 · 建筑加高 v05 · 2026-10-20

近、中、远三层建筑均通过内置imagegen重绘至约两倍高度。门洞、窗户、楼层层高、厂房与管廊同时调整。
所有图层scale=1，像素网格不变。人物、地面、挡土基座、坡道、碰撞、镜头缩放与奔跑速度保持原值。
建筑向上扩展256原生像素，三层画布6144×512，原点(0,-256)，物理世界仍6144×256。
原530452个地面像素逐一相同，ground_profile.json未改；对比校验见layer_info.json。

完整长图
battlefield_near_native.png / battlefield_mid_native.png / battlefield_far_native.png：6144×512。
对应 *_12288x1024.png 是精确2倍最近邻放大的完整长图。
近、中、远横向速度：1.0 / 0.58 / 0.28，透明层alpha仅0/255。
使用上一版各层调色板，中景校准明度，保留钢灰、灰褐、锈色、黄沙的工业配色和明暗关系。

实际试玩图
*_preview_4x.png来自Godot实际320×180截图，最近邻放大4倍。
building_scale_before_after.png上方为v04、下方为v05，相同地图位置与镜头；人物及地面尺寸不变。
contact_sheet仅供分段检查；交付的长图为完整单行PNG。

试玩与工程
完整工程：https://github.com/cogco1/nightwalker
根目录双击Run-Battlefield.cmd。A/D移动，长按Shift奔跑，空格跳跃，R回起点，Esc退出。
source_code保存本次更新源码，依赖完整工程原有的人物、控制脚本与素材。
原主入口、安全屋、医院、夜街没有改动。

实际运行
Godot 4.7.2.stable.official.ed1daf0bf，版本核对及无窗口素材导入均退出0。
快速回归41项通过；GPU完整跑步130项通过。
距离6076.91原生像素，保存11张游戏截图。
中景比例0.580014，远景比例0.280048。
详细报告、图层可见像素匹配结果及日志见run_test_evidence。

源图与复现
24张内置imagegen原图分存near_sources、mid_sources、far_sources，各8张。
edit_inputs为旧图按768px裁段并向上扩展透明/天空画布的输入，未缩放原建筑。
完整提示词、内置工具模式和生成来源见generation_prompts.json。
按用户已授权的方法用本地Pillow/NumPy对齐、统一调色板、二值透明和拼接；未用竖向拉伸替代建筑重绘。
source_code/tools/build_battlefield_tall_layers.py为构建源码；layer_info.json记录实际尺寸、原点、明度校准、近中景各段高度统计与SHA256。
file_manifest.json为本地素材包文件SHA256清单。
修改前完整备份：Nightwalker_Backups/夜行者_建筑加高修改前_2026-10-20_bad01c6.zip。
