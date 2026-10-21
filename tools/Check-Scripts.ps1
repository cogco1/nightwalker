# Static checks without running the game:
# - every PowerShell script in the repository starts with a UTF-8 BOM and parses in Windows PowerShell 5.1;
# - every GDScript under game/ loads with Godot --check-only (directories with a .gdignore are skipped, as Godot
#   skips them).
# Godot logs: game/evidence/logs/check_*.log. -SkipImport when Test-Game.ps1 has just imported the assets.
param([string]$GodotPath = '', [switch]$SkipImport)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$failed = @()
# Without a BOM, Windows PowerShell 5.1 decodes a script in the system code page (GBK on Chinese Windows), where a
# Chinese string can swallow its closing quote. The parse below uses this machine's code page, so the BOM is
# checked on its own.
$repositoryRoot = (Resolve-Path -LiteralPath $NightwalkerRoot).Path.TrimEnd('\')
$powershellScripts = @(Get-ChildItem -LiteralPath $repositoryRoot -Recurse -File -Filter '*.ps1' |
    Where-Object { $_.FullName -notmatch '\\(\.git|\.godot)\\' } | Sort-Object FullName)
foreach ($file in $powershellScripts) {
    $relative = $file.FullName.Substring($repositoryRoot.Length + 1).Replace('\', '/')
    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    if ($bytes.Length -lt 3 -or $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) {
        $failed += $relative
        '{0} FAIL 缺少 UTF-8 BOM' -f $relative
        continue
    }
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        $failed += $relative
        '{0} FAIL 第 {1} 行：{2}' -f $relative, $errors[0].Extent.StartLineNumber, $errors[0].Message
    }
}

$godot = Get-NightwalkerGodot $GodotPath
if (-not $SkipImport) { Invoke-NightwalkerImport $godot }
$projectRoot = (Resolve-Path -LiteralPath $NightwalkerProject).Path.TrimEnd('\')
$ignored = @(Get-ChildItem -LiteralPath $projectRoot -Recurse -Force -File -Filter '.gdignore' | ForEach-Object { $_.DirectoryName + '\' })
$gdscripts = @(Get-ChildItem -LiteralPath $projectRoot -Recurse -File -Filter '*.gd' | Where-Object {
    $path = $_.FullName
    -not $path.StartsWith($projectRoot + '\.godot\') -and -not ($ignored | Where-Object { $path.StartsWith($_) })
} | Sort-Object FullName)
foreach ($script in $gdscripts) {
    $relative = $script.FullName.Substring($projectRoot.Length + 1).Replace('\', '/')
    $logName = 'check_' + ($relative -replace '[/\\.]', '_')
    $result = Invoke-NightwalkerGodot $godot @('--headless', '--check-only', '--script', ('res://' + $relative)) $logName 120
    if ($result.Failed) {
        $failed += 'game/' + $relative
        'game/{0} FAIL exit={1}' -f $relative, $result.ExitCode
        Get-Content -LiteralPath $result.ErrorLog -Tail 5 -Encoding UTF8 | ForEach-Object { '    ' + $_ }
    }
}
'-' * 48
'{0} 个 PowerShell 脚本，{1} 个 GDScript，失败 {2} 个。日志：{3}' -f $powershellScripts.Count, $gdscripts.Count, $failed.Count, $NightwalkerLogs
if ($failed.Count -gt 0) {
    '失败：' + ($failed -join ', ')
    exit 1
}
