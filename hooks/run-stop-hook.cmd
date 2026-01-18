@echo off
setlocal

REM Persistent Ralph - Stop Hook Windows Wrapper
REM Creates a temporary wrapper and uses sh -c '. wrapper' to execute

set "SCRIPT_DIR=%~dp0"
set "SH_PATH=C:\Program Files\Git\bin\sh.exe"

if not exist "%SH_PATH%" (
    echo {}
    exit /b 0
)

REM Convert Windows path to Unix path
set "UNIX_SCRIPT_DIR=%SCRIPT_DIR:\=/%"
set "UNIX_CD=%CD:\=/%"

REM Create temp wrapper script (avoids cmd escaping issues with special chars)
set "TEMP_WRAPPER=%TEMP%\ralph-stop-wrapper-%RANDOM%.sh"
set "UNIX_TEMP_WRAPPER=%TEMP_WRAPPER:\=/%"

(
echo #!/bin/sh
echo cd "%UNIX_CD%"
echo export SCRIPT_DIR="%UNIX_SCRIPT_DIR%"
echo . "$SCRIPT_DIR/stop-hook.sh"
) > "%TEMP_WRAPPER%"

REM Execute using sh -c '. wrapper' to get proper stdout
"%SH_PATH%" -c ". '%UNIX_TEMP_WRAPPER%'"
set "EXIT_CODE=%ERRORLEVEL%"

REM Cleanup
del "%TEMP_WRAPPER%" 2>nul

exit /b %EXIT_CODE%
