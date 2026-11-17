@echo off
rem Clawd'i gunluk tutarak baslatir. Sorun olursa olusan clawd-gunluk.txt dosyasina bak.
cd /d "%~dp0"
taskkill /im Clawd.exe /f >nul 2>&1
del clawd-gunluk.txt >nul 2>&1
start "" "%~dp0Clawd.exe" -gunluk 1
