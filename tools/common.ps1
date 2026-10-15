# Shared helpers for Run-Game.ps1 and Test-Game.ps1. Dot-source this file.
$NightwalkerRoot = Split-Path -Parent $PSScriptRoot
$NightwalkerProject = Join-Path $NightwalkerRoot 'game'
$NightwalkerLogs = Join-Path $NightwalkerProject 'evidence\logs'

# Godot lookup order: -GodotPath, $env:NIGHTWALKER_GODOT, <repo>\godot-path.txt, godot/godot4 on PATH, Godot*.exe in the repo root.
function Get-NightwalkerGodot([string]$GodotPath = '') {
    if (-not $GodotPath -and $env:NIGHTWALKER_GODOT) { $GodotPath = $env:NIGHTWALKER_GODOT }
    $pathFile = Join-Path $NightwalkerRoot 'godot-path.txt'
    if (-not $GodotPath -and (Test-Path -LiteralPath $pathFile)) {
        $GodotPath = (Get-Content -LiteralPath $pathFile -Raw -Encoding UTF8).Trim().Trim('"')
    }
    if (-not $GodotPath) {
        foreach ($name in @('godot', 'godot4')) {
            $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue
            if ($command) { $GodotPath = $command.Source; break }
        }
    }
    if (-not $GodotPath) {
        $local = Get-ChildItem -LiteralPath $NightwalkerRoot -File -Filter 'Godot*.exe' | Select-Object -First 1
        if ($local) { $GodotPath = $local.FullName }
    }
    if (-not $GodotPath -or -not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
        throw '没有找到 Godot 4.7.2。把 godot-path.example.txt 复制成 godot-path.txt 并写入本机 Godot 可执行文件路径，或设置环境变量 NIGHTWALKER_GODOT。'
    }
    return $GodotPath
}

# Runs Godot against game/ with hidden window; stdout/stderr go to evidence/logs/<LogName>.log and <LogName>_errors.log.
# A run that outlives TimeoutSeconds is killed and reported as failed instead of hanging the whole regression.
function Invoke-NightwalkerGodot([string]$Godot, [string[]]$Arguments, [string]$LogName, [int]$TimeoutSeconds = 300) {
    New-Item -ItemType Directory -Path $NightwalkerLogs -Force | Out-Null
    $out = Join-Path $NightwalkerLogs ($LogName + '.log')
    $err = Join-Path $NightwalkerLogs ($LogName + '_errors.log')
    $allArguments = @('--path', ('"' + $NightwalkerProject + '"')) + $Arguments
    $process = Start-Process -FilePath $Godot -ArgumentList $allArguments -WorkingDirectory $NightwalkerProject -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    # Touch the handle now: without it PowerShell 5.1 reports a null ExitCode for processes started without -Wait.
    $null = $process.Handle
    $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        Add-Content -LiteralPath $err -Value ('ERROR: timed out after ' + $TimeoutSeconds + ' s') -Encoding UTF8
    }
    $process.WaitForExit()
    $scriptErrors = Select-String -LiteralPath $err -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet
    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        TimedOut = $timedOut
        Failed   = $timedOut -or ($process.ExitCode -ne 0) -or $scriptErrors
        Output   = [string](Get-Content -LiteralPath $out -Raw -Encoding UTF8)
        Log      = $out
        ErrorLog = $err
    }
}

function Invoke-NightwalkerImport([string]$Godot) {
    $result = Invoke-NightwalkerGodot $Godot @('--headless', '--editor', '--import', '--quit') 'import'
    if ($result.Failed) { throw ('Godot 素材导入失败，请查看 ' + $result.ErrorLog) }
}
