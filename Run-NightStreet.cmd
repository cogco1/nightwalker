@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Run-Game.ps1" -Scene res://scenes/night_street_proto.tscn || pause
