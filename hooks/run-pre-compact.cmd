@echo off
setlocal enabledelayedexpansion

REM Persistent Ralph - PreCompact Hook Windows Wrapper
REM Executes pre-compact.sh using Git Bash

set "SCRIPT_DIR=%~dp0"
set "BASH_PATH=C:\Program Files\Git\bin\bash.exe"

if not exist "%BASH_PATH%" (
    exit /b 0
)

"%BASH_PATH%" "%SCRIPT_DIR%pre-compact.sh"
