@echo off
setlocal enabledelayedexpansion

REM Persistent Ralph - Auto-Resume Hook Windows Wrapper
REM Executes auto-resume.sh using Git Bash

set "SCRIPT_DIR=%~dp0"
set "BASH_PATH=C:\Program Files\Git\bin\bash.exe"

if not exist "%BASH_PATH%" (
    exit /b 0
)

REM Convert Windows path to Unix path and export SCRIPT_DIR so the script can find lib/
set "UNIX_SCRIPT_DIR=%SCRIPT_DIR:\=/%"

REM Use source (.) with SCRIPT_DIR env var to work around Windows subprocess output issues
"%BASH_PATH%" -c "cd \"%CD%\" && export SCRIPT_DIR='%UNIX_SCRIPT_DIR%' && . '%UNIX_SCRIPT_DIR%auto-resume.sh'"
