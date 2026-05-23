@echo off
setlocal

echo Noterr cloud sync setup
echo.
echo Paste your Supabase Project URL and anon public key.
echo These values will be saved only on this computer in sync_config.bat.
echo.

set "DEFAULT_SUPABASE_URL=https://mtiqvxjqamufuoicbkrk.supabase.co"
set /p SUPABASE_URL=Supabase URL [%DEFAULT_SUPABASE_URL%]: 
if "%SUPABASE_URL%"=="" set "SUPABASE_URL=%DEFAULT_SUPABASE_URL%"
set /p SUPABASE_ANON_KEY=Supabase anon key: 

if "%SUPABASE_URL%"=="" goto :missing
if "%SUPABASE_ANON_KEY%"=="" goto :missing
if /i not "%SUPABASE_URL%"=="%DEFAULT_SUPABASE_URL%" goto :wrong_project

(
  echo @echo off
  echo set "SUPABASE_URL=%SUPABASE_URL%"
  echo set "SUPABASE_ANON_KEY=%SUPABASE_ANON_KEY%"
) > "%~dp0sync_config.bat"

echo.
echo Sync config saved. You can now use:
echo   Run-Windows-Sync-Preview.bat
echo   Build-Android-Sync-Debug.bat
pause
exit /b 0

:missing
echo.
echo URL and anon key are both required.
pause
exit /b 1

:wrong_project
echo.
echo This setup is locked to the Noterr Supabase project:
echo %DEFAULT_SUPABASE_URL%
echo.
echo Refusing to save a different project URL so another project is not touched by mistake.
pause
exit /b 1
