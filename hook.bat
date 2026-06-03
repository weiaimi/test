@echo off
setlocal EnableDelayedExpansion
cd /d "%~dp0"

set "Pkg=com.greenpoint.android.mc10086.activity"
set "LibnetOff=133d0"
set "PlainBpOff=98"
set "Client=/data/local/tmp/wxshadow_client"

echo 前置: 已关机重启过; APatch 仅加载一份 wxshadow_cmcc.kpm  参数: cmcc
echo       加载前: adb shell am force-stop %Pkg%
echo       adb push dist\wxshadow_client %Client%
adb devices -l

adb shell su -c "test -x %Client% && echo ok" 2>nul | findstr /i "ok" >nul
if errorlevel 1 (
    echo 缺少 %Client%
    exit /b 1
)

echo.
echo [1] 确认已加载 wxshadow_cmcc.kpm ^(cmcc^)，按 Enter
pause >nul

echo [2] 打开中国移动 App，按 Enter
pause >nul

set "pidApp="
for /f "tokens=1" %%a in ('adb shell su -c "pidof %Pkg%" 2^>nul') do set "pidApp=%%a"
if not defined pidApp (
    echo App 未运行
    exit /b 1
)

set "bp="
for /f "delims=" %%a in ('adb shell su -c "base=$(grep libnet.so /proc/%pidApp%/maps 2>/dev/null ^| grep r-xp ^| head -1 ^| cut -d- -f1); if [ -n \"$base\" ]; then printf 0x%%x $((0x$base + 0x%LibnetOff% + 0x%PlainBpOff%)); fi" 2^>nul') do set "bp=%%a"
if not defined bp (
    echo libnet.so 未加载，先在 App 里触发一次网络请求
    exit /b 1
)

adb shell su -c "setenforce 0 2>/dev/null; true" >nul 2>&1
set "out="
for /f "delims=" %%a in ('adb shell su -c "%Client% -p %pidApp% -a %bp%" 2^>^&1') do (
    echo %%a
    set "out=%%a"
)
echo !out! | findstr /i "Breakpoint set" >nul
if errorlevel 1 exit /b 1

echo.
echo [3] 在 App 里触发加密 ^(~90s^)，等待 dmesg cmcc_plain...
set /a n=0
:poll
if !n! geq 90 goto timeout
timeout /t 1 /nobreak >nul
adb shell su -c "dmesg | grep cmcc_plain | tail -15" > "%TEMP%\cmcc_plain.txt" 2>nul
findstr /C:"cmcc_plain:" "%TEMP%\cmcc_plain.txt" | findstr /C:"{" >nul
if not errorlevel 1 (
    echo.
    echo ===== 明文 =====
    type "%TEMP%\cmcc_plain.txt"
    adb shell su -c "%Client% -p %pidApp% -d" >nul 2>&1
    exit /b 0
)
set /a n+=1
goto poll

:timeout
adb shell su -c "%Client% -p %pidApp% -d" >nul 2>&1
echo 未看到 cmcc_plain。请确认 KPM 加载参数为 cmcc：
echo   adb shell su -c "dmesg ^| grep cmcc_plain"
echo 离线加密: unidbg ChinaMobileNetClient
exit /b 1
