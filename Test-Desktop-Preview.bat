@echo off
setlocal

set "FLUTTER=C:\tmp\flutter\bin\flutter.bat"
set "APP_DIR=C:\tmp\NoterrBuild"
set "SOURCE_DIR=C:\Users\zubai\Documents\Noterr"

if not exist "%FLUTTER%" (
  echo Flutter was not found at %FLUTTER%.
  pause
  exit /b 1
)

if not exist "%APP_DIR%" (
  echo Test project was not found at %APP_DIR%.
  pause
  exit /b 1
)

pushd "%APP_DIR%"
copy "%SOURCE_DIR%\pubspec.yaml" "%APP_DIR%\pubspec.yaml" >nul || goto :fail
robocopy "%SOURCE_DIR%\lib" "%APP_DIR%\lib" /MIR >nul
if errorlevel 8 goto :fail
robocopy "%SOURCE_DIR%\test" "%APP_DIR%\test" /MIR >nul
if errorlevel 8 goto :fail
call "%FLUTTER%" pub get || goto :fail
call "%FLUTTER%" analyze || goto :fail
call "%FLUTTER%" test test\widget_test.dart test\sticky_window_payload_test.dart || goto :fail
call "%FLUTTER%" run -d windows
popd
exit /b 0

:fail
popd
echo.
echo Preview stopped because one of the test steps failed.
pause
exit /b 1
