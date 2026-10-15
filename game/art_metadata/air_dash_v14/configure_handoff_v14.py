"""Set up portable launchers and the complete test entry for the integrated game."""
import shutil
from pathlib import Path

BASE = Path(__file__).resolve().parent / 'integration_v14'
OUTPUTS = BASE / 'outputs'
GAME = OUTPUTS / 'Current_Game'
for name in ['Open-Editor.cmd', 'Run-Demo.cmd', 'Test-Game.cmd']:
    shutil.copy2(BASE / 'original_v10' / name, OUTPUTS / name)
(OUTPUTS / 'godot-path.txt').write_text('D:/浏览器下载/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe', encoding='utf-8-sig')
tests = r'''param([string]$GodotPath = '')
$ErrorActionPreference = 'Stop'
if (-not $GodotPath) {
    $GodotPath = (Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'godot-path.txt') -Raw -Encoding UTF8).Trim().Trim('"')
}
& (Join-Path $PSScriptRoot 'Run-Game.ps1') -GodotPath $GodotPath -Test -BindingsTest -AirTest
foreach ($suite in @('test_air_dash_animation_v14','test_scene_integration_v14','test_hospital_interactions','test_hospital_environment','test_hospital_physical_stairs','test_hospital_ward_layout','test_hospital_security')) {
    $outLog = Join-Path $PSScriptRoot ('evidence/' + $suite + '_v14.log')
    $errLog = Join-Path $PSScriptRoot ('evidence/' + $suite + '_errors_v14.log')
    $quotedProject = '"' + $PSScriptRoot + '"'
    $process = Start-Process -FilePath $GodotPath -ArgumentList @('--headless','--fixed-fps','60','--path',$quotedProject,'--script',('res://tests/' + $suite + '.gd')) -WindowStyle Hidden -PassThru -Wait -RedirectStandardOutput $outLog -RedirectStandardError $errLog
    Get-Content -LiteralPath $outLog
    Get-Content -LiteralPath $errLog
    if ($process.ExitCode -ne 0 -or (Select-String -LiteralPath $errLog -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet)) {
        throw ('Regression failed: ' + $suite)
    }
}
'''
(GAME / 'Test-Game.ps1').write_text(tests, encoding='utf-8-sig')
(GAME / '操作说明.txt').write_text('''《夜行者》v14 · 安全屋、医院与独立空中突刺

启动 Run-Demo.cmd，默认进入601安全屋。场景中只有当前玩家，不放NPC或训练木桩。
WASD俯视移动；AD侧视移动；Caps按住跑步；空格跳跃，再按一次二段跳。
鼠标左键逐次点击三连击；W+左键地面上挑；Shift+A/D+新一次左键进行48像素突刺。
空中突刺使用独立收腿前冲动作，结束接回滞空，保留0.30秒、6像素/秒缓降；松开Shift或方向后点击左键接空中三连，S下劈。
侧视地面S下蹲，空中S下劈。第三刀30%三倍暴击、普通/暴击命中顿帧保持。
家中门口E进入医院；医院二楼办公室出口E回家。F7可快速切换两处场景。
医院Tab切换同一建筑的俯视/侧视；楼梯E上下楼，侧视W/E选上行、S/E选下行，AD踩实体楼梯自由行走。
F1打开按键设置；Esc关闭对话、密码框或设置；没有阅读界面时Esc也可打开设置。R重置当前位置。
F6训练场入口已移除。旧战斗环境只保留在tests/fixtures作为自动回归夹具，不参与正式游戏流程。

医院俯视：药品库、诊疗室、办公室三扇门均为密码1010，E输入、Enter确认、Esc取消；侧视不添加门禁。
俯视配电柜需要breaker_key。钥匙领取事件留待后续NPC对话制作，当前地图不随意放钥匙或密码提示。
后续对话可调用/root/NightwalkerStoryState.grant_item("breaker_key")；门、电柜与电源状态在本次游戏会话内跨场景保留。

世界以320×180逻辑坐标、原生整数像素和最近邻整数放大显示，人物scale=1。
已批准的12px字幕、48×64立绘与80%对话UI保留；UI在窗口分辨率合成，避免缩放中文字缺笔。
新动作原画、两次完整提示词、参考、刀尖分析与导入脚本见art_metadata/air_dash_v14。
换电脑请修改上一级godot-path.txt。Test-Game.ps1 -GodotPath '<Godot路径>'运行完整检查。
''', encoding='utf-8')
(GAME / '本版更新.txt').write_text('''v14：以用户提供的空中突刺v10工程为角色基线，融合安全屋和地下医院。
新增air_dash_stab_right/left各16帧、40fps，112×96画布，固定足点(56,84)。
原992帧、地面突刺、原刀尖路径与物理参数保持。player.gd只增加两行动画选择，没有新增空中状态或运行时循环。
原有二段跳、上挑、空中三连、下劈和落地冲击、暴击与顿帧保留。
正式入口为安全屋；E家门/医院出口往返，F7快捷往返，F6训练场入口删除。
按键菜单和命中停顿通过共享GameSession连接到两处场景，阅读与密码输入会清空攻击缓冲。
医院俯视密码1010和钥匙电柜保留；暂不放NPC，后续对话可发放钥匙。
''', encoding='utf-8')
(GAME / '交付说明.txt').write_text('''夜行者v14完整工程
Current_Game/project.godot可直接用Godot4.7.2打开。上一级Run-Demo.cmd启动，Open-Editor.cmd打开编辑器，Test-Game.cmd测试。
以输入ZIP的player场景、控制器、992原始动作帧和原空战手感为基线，仅新增左右32帧收腿突刺。
安全屋和医院复用前版美术、交互、双视角分层与实体楼梯。正式场景没有训练目标、NPC或旧角色副本。
scripts/game_session.gd共用按键设置与命中停顿；scripts/scene_routes.gd只允许安全屋和医院跳转。
原战斗回归环境位于tests/fixtures；原基线717项已在独立副本实际复核，新增动作更新资源计数检查。
art_metadata/air_dash_v14保存全部新增原画、提示词、技术导入和校验，使用内置image_gen。
当前运行结果、源码包及修改前备份见上一级outputs目录。
''', encoding='utf-8')
print('Configured v14 launchers, controls guide and full regression entry')
