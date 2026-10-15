param([string]$GodotPath = '', [switch]$Editor, [switch]$Test, [switch]$BindingsTest, [switch]$AirTest)
$ErrorActionPreference = 'Stop'
$projectDirectory = $PSScriptRoot
$handoffRoot = Split-Path -Parent $projectDirectory
if (-not $GodotPath -and $env:NIGHTWALKER_GODOT) { $GodotPath = $env:NIGHTWALKER_GODOT }
$pathFile = Join-Path $handoffRoot 'godot-path.txt'
if (-not $GodotPath -and (Test-Path -LiteralPath $pathFile)) {
    $GodotPath = (Get-Content -LiteralPath $pathFile -Raw -Encoding UTF8).Trim().Trim('"')
}
if (-not $GodotPath) {
    foreach ($commandName in @('godot', 'godot4')) {
        $command = Get-Command $commandName -CommandType Application -ErrorAction SilentlyContinue
        if ($command) { $GodotPath = $command.Source; break }
    }
}
if (-not $GodotPath) {
    $localEngine = Get-ChildItem -LiteralPath $handoffRoot -File -Filter 'Godot*.exe' | Select-Object -First 1
    if ($localEngine) { $GodotPath = $localEngine.FullName }
}
if (-not $GodotPath) {
    $GodotPath = (Read-Host '请输入本机 Godot 4.7.2 可执行文件路径').Trim().Trim('"')
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw '没有找到 Godot。请修改根目录 godot-path.txt，或使用 -GodotPath 指定可执行文件。'
}
$quotedProject = '"' + $projectDirectory + '"'
if ($Editor) {
    Start-Process -FilePath $GodotPath -ArgumentList @('--editor', '--path', $quotedProject) -WorkingDirectory $projectDirectory -WindowStyle Normal
    return
}
$evidenceDirectory = Join-Path $projectDirectory 'evidence'
New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
$importProcess = Start-Process -FilePath $GodotPath -ArgumentList @('--headless', '--editor', '--path', $quotedProject, '--import', '--quit') -WorkingDirectory $projectDirectory -WindowStyle Hidden -PassThru -Wait -RedirectStandardOutput (Join-Path $evidenceDirectory 'handoff_import.log') -RedirectStandardError (Join-Path $evidenceDirectory 'handoff_import_errors.log')
if ($importProcess.ExitCode -ne 0 -or (Select-String -LiteralPath (Join-Path $evidenceDirectory 'handoff_import_errors.log') -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet)) { throw 'Godot 素材导入失败，请查看 evidence/handoff_import_errors.log。' }
if ($Test) {
    $testProcess = Start-Process -FilePath $GodotPath -ArgumentList @('--headless', '--fixed-fps', '60', '--path', $quotedProject, '--script', 'res://tests/test_v07.gd') -WorkingDirectory $projectDirectory -WindowStyle Hidden -PassThru -Wait -RedirectStandardOutput (Join-Path $evidenceDirectory 'tests_v07.log') -RedirectStandardError (Join-Path $evidenceDirectory 'tests_v07_errors.log')
    Get-Content -LiteralPath (Join-Path $evidenceDirectory 'tests_v07.log')
    Get-Content -LiteralPath (Join-Path $evidenceDirectory 'tests_v07_errors.log')
    if ($testProcess.ExitCode -ne 0 -or (Select-String -LiteralPath (Join-Path $evidenceDirectory 'tests_v07_errors.log') -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet)) { throw 'Godot 功能检查失败。' }
}
if ($BindingsTest) {
    foreach ($stage in @('keybindings', 'keybindings_reload')) {
        $testArguments = @('--headless', '--fixed-fps', '60', '--path', $quotedProject, '--script', 'res://tests/test_keybindings.gd')
        if ($stage -eq 'keybindings_reload') { $testArguments += @('--', '--reload-profile') }
        $stdout = Join-Path $evidenceDirectory ($stage + '.log')
        $stderr = Join-Path $evidenceDirectory ($stage + '_errors.log')
        $bindingProcess = Start-Process -FilePath $GodotPath -ArgumentList $testArguments -WorkingDirectory $projectDirectory -WindowStyle Hidden -PassThru -Wait -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        Get-Content -LiteralPath $stdout
        Get-Content -LiteralPath $stderr
        if ($bindingProcess.ExitCode -ne 0 -or (Select-String -LiteralPath $stderr -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet)) { throw 'Godot 改键功能检查失败。' }
    }
}
if ($AirTest) {
    $airOut = Join-Path $evidenceDirectory 'air_combat.log'
    $airErrors = Join-Path $evidenceDirectory 'air_combat_errors.log'
    $airProcess = Start-Process -FilePath $GodotPath -ArgumentList @('--headless', '--fixed-fps', '60', '--path', $quotedProject, '--script', 'res://tests/test_air_combat.gd') -WorkingDirectory $projectDirectory -WindowStyle Hidden -PassThru -Wait -RedirectStandardOutput $airOut -RedirectStandardError $airErrors
    Get-Content -LiteralPath $airOut
    Get-Content -LiteralPath $airErrors
    if ($airProcess.ExitCode -ne 0 -or (Select-String -LiteralPath $airErrors -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet)) { throw 'Godot 空战功能检查失败。' }
}
if ($Test -or $BindingsTest -or $AirTest) { return }
Start-Process -FilePath $GodotPath -ArgumentList @('--path', $quotedProject) -WorkingDirectory $projectDirectory -WindowStyle Normal
