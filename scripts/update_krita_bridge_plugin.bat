@echo off
setlocal

pushd "%~dp0\.." >nul || exit /b 1

echo [NAI Launcher Bridge] Checking current Krita profile...
python krita_plugin\install_plugin.py --check
if %ERRORLEVEL% EQU 0 (
    echo [NAI Launcher Bridge] Current profile already matches this checkout.
    popd >nul
    exit /b 0
) else (
    echo [NAI Launcher Bridge] Current profile is missing or stale. Installing latest plugin...
)

tasklist /FI "IMAGENAME eq krita.exe" 2>nul | find /I "krita.exe" >nul
if %ERRORLEVEL% EQU 0 (
    echo [NAI Launcher Bridge] Krita is running. Close Krita before updating the plugin.
    popd >nul
    exit /b 1
)

python krita_plugin\install_plugin.py --apply
set EXIT_CODE=%ERRORLEVEL%
if NOT "%EXIT_CODE%"=="0" (
    echo [NAI Launcher Bridge] Install failed or post-install verification failed.
    popd >nul
    exit /b %EXIT_CODE%
)

echo [NAI Launcher Bridge] Verifying installed profile...
python krita_plugin\install_plugin.py --check
set EXIT_CODE=%ERRORLEVEL%
popd >nul

exit /b %EXIT_CODE%
