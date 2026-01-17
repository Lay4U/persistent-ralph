@echo off
setlocal enabledelayedexpansion

REM Persistent Ralph - Stop Hook Windows Wrapper
REM Executes stop-hook.sh using Git Bash

set "SCRIPT_DIR=%~dp0"
set "BASH_PATH=C:\Program Files\Git\bin\bash.exe"

if not exist "%BASH_PATH%" (
    echo {"decision": null}
    exit /b 0
)

"%BASH_PATH%" "%SCRIPT_DIR%stop-hook.sh"
