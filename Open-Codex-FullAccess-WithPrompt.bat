@echo off
cd /d "%~dp0"
"C:\Users\zubai\AppData\Local\OpenAI\Codex\bin\3f4fb8cdd344abc7\codex.exe" -C "%~dp0" --sandbox danger-full-access --ask-for-approval on-request
