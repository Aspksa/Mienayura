@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Mienayura
rem Always resolve relative to this BAT, including Unicode paths and external drives.
set "MIENAYURA_ROOT=%~dp0"
if not exist "%MIENAYURA_ROOT%tools\launcher.ps1" (
  echo [ERROR] Missing tools\launcher.ps1
  pause
  exit /b 2
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%MIENAYURA_ROOT%tools\launcher.ps1" -ProjectRoot "%MIENAYURA_ROOT%" %*
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" (
  echo [ERROR] Launcher exited with code %EXITCODE%.
  rem Do not block CI or automated checks with a pause.
)
exit /b %EXITCODE%
