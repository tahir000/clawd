@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
title Clawd derleniyor

rem Windows 10 ve 11'in içinde gelen C# derleyicisi kullanılır; ayrıca program kurmak gerekmez.
set "FW=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319"
if not exist "%FW%\csc.exe" set "FW=%WINDIR%\Microsoft.NET\Framework\v4.0.30319"
if not exist "%FW%\csc.exe" (
    echo Derleyici bulunamadı: %FW%\csc.exe
    echo Bu pencerenin görüntüsüyle depoda bir kayıt açabilirsin.
    pause
    exit /b 1
)

taskkill /im Clawd.exe /f >nul 2>&1

"%FW%\csc.exe" /nologo /noconfig /codepage:65001 /target:winexe /optimize+ /platform:anycpu /out:Clawd.exe /win32icon:Clawd.ico ^
    /r:System.dll /r:System.Core.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll ^
    /r:"%FW%\WPF\WindowsBase.dll" /r:"%FW%\WPF\UIAutomationClient.dll" /r:"%FW%\WPF\UIAutomationTypes.dll" ^
    Clawd.cs
if errorlevel 1 (
    echo.
    echo Derleme başarısız oldu. Bu pencerenin görüntüsüyle depoda bir kayıt açabilirsin.
    pause
    exit /b 1
)

echo Clawd hazır, başlatılıyor. Sağ tıklayınca menüsü açılır.
start "" "%~dp0Clawd.exe"
timeout /t 3 >nul
