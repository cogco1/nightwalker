@echo off
chcp 65001 >nul
setlocal
set "ENEMY_GODOT=%~1"
if not defined ENEMY_GODOT set "ENEMY_GODOT=D:\浏览器下载\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
if not exist "%ENEMY_GODOT%" (
  echo Godot executable was not found.
  echo Drag Godot.exe onto this .cmd, or run: Open-Enemy-Gallery.cmd "C:\path\Godot.exe"
  pause
  exit /b 1
)
start "" /wait "%ENEMY_GODOT%" --headless --editor --path "%~dp0preview_project" --import --quit
if errorlevel 1 (
  echo Godot import failed. Please open preview_project/project.godot in the editor for diagnostics.
  pause
  exit /b 1
)
start "" "%ENEMY_GODOT%" --path "%~dp0preview_project" --resolution 1280x720
