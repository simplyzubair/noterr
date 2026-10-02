@echo off
setlocal

set "FLUTTER=C:\tmp\flutter\bin\flutter.bat"
set "APP_DIR=C:\tmp\NoterrBuild"
set "SOURCE_DIR=C:\Users\zubai\Documents\Noterr"

pushd "%APP_DIR%" || exit /b 1
copy "%SOURCE_DIR%\pubspec.yaml" "%APP_DIR%\pubspec.yaml" >nul
robocopy "%SOURCE_DIR%\lib" "%APP_DIR%\lib" /MIR >nul
robocopy "%SOURCE_DIR%\test" "%APP_DIR%\test" /MIR >nul
call "%FLUTTER%" pub get || goto :fail
call "%FLUTTER%" devices
echo.
echo If your phone is listed above, this will open Noterr on Android.
echo Keep this window open while testing.
pause
call "%FLUTTER%" run -d android
popd
exit /b 0

:fail
popd
echo Android preview failed.
pause
exit /b 1
