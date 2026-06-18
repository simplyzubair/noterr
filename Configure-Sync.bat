@echo off
setlocal

echo Configure Noterr Cloudflare sync.
echo.
echo Paste the Noterr Worker URL.
echo Example: https://noterr-sync.YOUR-SUBDOMAIN.workers.dev
echo.

set /p NOTERR_SYNC_URL=Cloudflare Worker URL: 

if "%NOTERR_SYNC_URL%"=="" goto :missing

(
  echo set "NOTERR_SYNC_URL=%NOTERR_SYNC_URL%"
) > "%~dp0sync_config.bat"

echo.
echo Saved sync_config.bat
echo.
pause
exit /b 0

:missing
echo.
echo Missing Worker URL.
pause
exit /b 1
