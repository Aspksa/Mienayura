@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
title Mienayura - Start
cd /d "%~dp0"
set "ROOT=%CD%"
set "LOGDIR=%ROOT%\logs"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
set "LOG=%LOGDIR%\startup.log"
echo ==== %DATE% %TIME% ====>>"%LOG%"
echo [Mienayura] Starting from "%ROOT%"
where node.exe >nul 2>&1
if errorlevel 1 goto :no_node
where npm.cmd >nul 2>&1
if errorlevel 1 goto :no_npm
if not exist "package.json" goto :no_project
if not exist "node_modules" (
  echo [Mienayura] Installing dependencies...
  if exist "package-lock.json" (
    call npm.cmd ci >>"%LOG%" 2>&1
  ) else (
    call npm.cmd install >>"%LOG%" 2>&1
  )
  if errorlevel 1 goto :install_failed
)
echo [Mienayura] Launching...
call npm.cmd run start >>"%LOG%" 2>&1
if not errorlevel 1 goto :done
echo [Mienayura] Start failed. Check "%LOG%"
goto :failed
:no_node
echo [ERROR] Node.js not installed. Install LTS from https://nodejs.org/
goto :failed
:no_npm
echo [ERROR] npm.cmd not found. Reinstall Node.js LTS.
goto :failed
:no_project
echo [Mienayura] Project is not initialized yet: package.json is missing.
echo [Mienayura] The launcher is ready for the application source.
goto :done
:install_failed
echo [ERROR] Dependency installation failed. See "%LOG%"
goto :failed
:failed
pause
exit /b 1
:done
echo [Mienayura] Finished.
pause
exit /b 0
