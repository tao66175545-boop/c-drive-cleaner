@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
cd /d "%SCRIPT_DIR%"

if not exist "%SCRIPT_DIR%C-Drive-Cleaner-UI.ps1" (
    exit /b 1
)

start "" /b "%PS_EXE%" -WindowStyle Hidden -STA -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%C-Drive-Cleaner-UI.ps1"
exit /b 0
