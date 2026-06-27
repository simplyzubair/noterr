@echo off
setlocal

echo Configure Noterr Cloudflare sync.
echo.
echo Paste the Noterr Worker URL.
echo Example: https://noterr-sync.YOUR-SUBDOMAIN.workers.dev
echo.

set /p NOTERR_SYNC_URL=Cloudflare Worker URL: 

if "%NOTERR_SYNC_URL%"=="" goto :missing
echo %NOTERR_SYNC_URL% | findstr /i "welcome.developers.workers.dev wrangler-oauth-consent-granted" >nul
if not errorlevel 1 goto :invalid
echo %NOTERR_SYNC_URL% | findstr /i /r "^https://.*" >nul
if errorlevel 1 goto :invalid

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

:invalid
echo.
echo That does not look like the Noterr sync Worker URL.
echo Use the deployed URL, for example:
echo   https://noterr-sync.YOUR-SUBDOMAIN.workers.dev
echo Do not use the Cloudflare login or welcome URL.
pause
exit /b 1
