@echo off
setlocal enabledelayedexpansion

REM Get the directory where this script is located
set "SCRIPT_DIR=%~dp0"

REM Remove trailing backslash
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

REM Run the bash script using Git Bash
"C:\Program Files\Git\bin\bash.exe" "%SCRIPT_DIR%\prompt-replace.sh"
