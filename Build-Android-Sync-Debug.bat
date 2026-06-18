@echo off
setlocal

set "FLUTTER=C:\tmp\flutter\bin\flutter.bat"
set "APP_DIR=C:\tmp\NoterrBuild"
set "SOURCE_DIR=C:\Users\zubai\Documents\Noterr"
set "CONFIG=%SOURCE_DIR%\sync_config.bat"

if not exist "%CONFIG%" goto :missing_config
call "%CONFIG%"
if "%NOTERR_SYNC_URL%"=="" goto :missing_config

pushd "%APP_DIR%" || exit /b 1
copy "%SOURCE_DIR%\pubspec.yaml" "%APP_DIR%\pubspec.yaml" >nul
robocopy "%SOURCE_DIR%\lib" "%APP_DIR%\lib" /MIR >nul
if errorlevel 8 goto :fail
robocopy "%SOURCE_DIR%\test" "%APP_DIR%\test" /MIR >nul
if errorlevel 8 goto :fail
call "%FLUTTER%" pub get || goto :fail
call "%FLUTTER%" build apk --debug --dart-define=NOTERR_SYNC_URL="%NOTERR_SYNC_URL%" || goto :fail
echo.
echo Sync APK created:
echo %APP_DIR%\build\app\outputs\flutter-apk\app-debug.apk
pause
popd
exit /b 0

:missing_config
echo Sync is not configured yet.
echo Run Configure-Sync.bat first, then try this again.
pause
exit /b 1

:fail
popd
echo Android sync APK build failed.
pause
exit /b 1
