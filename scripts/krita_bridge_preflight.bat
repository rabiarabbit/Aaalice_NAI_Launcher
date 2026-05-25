@echo off
chcp 65001 >nul
setlocal

cd /d "%~dp0\.."

echo ==========================================
echo   NAI Launcher - Krita Bridge Preflight
echo ==========================================
echo.
echo This command is read-only for the real Krita profile.
echo It packages the plugin, checks the current profile with --check,
echo and regenerates the acceptance report.
echo.

set "PYTHON_CMD="
set "WSL_CWD="
where py >nul 2>nul
if %errorlevel% equ 0 (
    set "PYTHON_CMD=py -3"
) else (
    where python >nul 2>nul
    if %errorlevel% equ 0 (
        set "PYTHON_CMD=python"
    )
)

if "%PYTHON_CMD%"=="" (
    where wsl.exe >nul 2>nul
    if %errorlevel% equ 0 (
        for /f "usebackq delims=" %%p in (`wsl.exe wslpath -a "%CD%"`) do set "WSL_CWD=%%p"
    )
)

if not "%PYTHON_CMD%"=="" (
    %PYTHON_CMD% krita_plugin\preflight.py %*
    set "EXIT_CODE=%errorlevel%"
    goto :after_preflight
)

if not "%WSL_CWD%"=="" (
    wsl.exe --cd "%WSL_CWD%" python3 krita_plugin/preflight.py %*
    set "EXIT_CODE=%errorlevel%"
    goto :after_preflight
)

if "%PYTHON_CMD%"=="" if "%WSL_CWD%"=="" (
    echo [ERROR] Python was not found on PATH.
    echo Install Python 3 or run from WSL: python3 krita_plugin/preflight.py %*
    exit /b 1
)

:after_preflight
if not "%EXIT_CODE%"=="0" (
    echo.
    echo [ERROR] Krita Bridge preflight failed with exit code %EXIT_CODE%.
    exit /b %EXIT_CODE%
)

echo.
echo [OK] Krita Bridge preflight finished.
exit /b 0
