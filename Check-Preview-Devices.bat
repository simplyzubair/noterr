@echo off
setlocal

set "FLUTTER=C:\tmp\flutter\bin\flutter.bat"
call "%FLUTTER%" devices
echo.
echo Android devices need USB debugging enabled, or an Android emulator running.
pause
