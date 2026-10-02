@echo off
setlocal

cd /d "%~dp0cloudflare" || exit /b 1

echo This deploys the Noterr sync Worker to Cloudflare.
echo If Wrangler asks you to log in, approve it in the browser and run this file again.
echo.

npx wrangler deploy
if errorlevel 1 goto :fail

echo.
echo Copy the workers.dev URL from above, then run Configure-Sync.bat.
echo.
pause
exit /b 0

:fail
echo.
echo Deploy failed. If the message mentions login or CLOUDFLARE_API_TOKEN,
echo run this command in PowerShell:
echo.
echo   cd "%~dp0cloudflare"
echo   npx wrangler login
echo   npx wrangler deploy
echo.
pause
exit /b 1
