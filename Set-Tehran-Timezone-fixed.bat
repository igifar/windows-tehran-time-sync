@echo off
title Set Tehran Timezone + Sync Time
color 0A
setlocal EnableDelayedExpansion

echo.
echo  ========================================================
echo       Set Tehran Timezone + Sync System Time
echo  ========================================================
echo.

:: ---------- Admin check ----------
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo  [!] Requesting Administrator access...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:: ---------- 1. Timezone ----------
echo  [1/4] Setting timezone to Tehran...
tzutil /s "Iran Standard Time" >nul 2>&1
if errorlevel 1 (
    echo       [ERROR] Failed to set timezone
) else (
    echo       OK - Iran Standard Time
)
echo.

:: ---------- 2. Windows Time service ----------
echo  [2/4] Preparing Windows Time service...
sc query w32time >nul 2>&1
if errorlevel 1 w32tm /register >nul 2>&1
sc config w32time start= auto >nul 2>&1
sc query w32time | find "RUNNING" >nul || net start w32time >nul 2>&1
echo       Time service is ready
echo.

:: ---------- 3. Sync ----------
echo  [3/4] Synchronizing time...
set "SYNC_OK=0"

call :ntp_sync "Iran" "ntp.iranet.ir,0x1 ntp.time.ir,0x1 0.ir.pool.ntp.org,0x1 1.ir.pool.ntp.org,0x1 2.ir.pool.ntp.org,0x1 185.13.228.162,0x1 194.146.239.1,0x1 194.146.239.10,0x1"
if "!SYNC_OK!"=="0" call :ntp_sync "Asia/Global" "0.asia.pool.ntp.org,0x1 1.asia.pool.ntp.org,0x1 time.windows.com,0x1 time.google.com,0x1 time.cloudflare.com,0x1 time.nist.gov,0x1 pool.ntp.org,0x1"
if "!SYNC_OK!"=="0" call :http_sync
echo.

:: ---------- 4. Status ----------
echo  [4/4] Final status
echo  ========================================================
echo  Timezone : & tzutil /g
echo  Date/Time: %date%  %time%
echo  Source   : & w32tm /query /source 2>nul
echo.
if "!SYNC_OK!"=="1" (
    echo  [SUCCESS] Time has been synchronized.
) else (
    echo  [WARNING] Could not sync time from any source.
    echo            Check internet / VPN / firewall (UDP 123 may be blocked).
    echo            If the time resets after every shutdown, replace the
    echo            motherboard CMOS battery.
)
echo  ========================================================
echo.
pause
endlocal
exit /b

:: ============================================================
:ntp_sync
echo       Trying %~1 NTP servers...
w32tm /config /manualpeerlist:"%~2" /syncfromflags:manual /update >nul 2>&1
net stop w32time >nul 2>&1
net start w32time >nul 2>&1
for /l %%i in (1,1,3) do (
    if "!SYNC_OK!"=="0" (
        timeout /t 3 /nobreak >nul
        w32tm /resync /rediscover >nul 2>&1
        if !errorLevel! equ 0 set "SYNC_OK=1"
    )
)
if "!SYNC_OK!"=="1" (
    echo       [OK] Synced via %~1 NTP servers
) else (
    echo       [x] %~1 NTP servers failed
)
goto :eof

:: ============================================================
:http_sync
echo       NTP failed. Trying HTTPS time (Date header)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; foreach($u in 'https://www.digikala.com','https://www.google.com','https://www.cloudflare.com','https://www.microsoft.com'){ try{ $r=Invoke-WebRequest -Uri $u -Method Head -UseBasicParsing -TimeoutSec 8; $d=[DateTimeOffset]::Parse([string]$r.Headers['Date']); Set-Date -Date $d.LocalDateTime | Out-Null; Write-Host ('      [OK] Time set from ' + $u); exit 0 }catch{} }; exit 1"
if !errorLevel! equ 0 set "SYNC_OK=1"
goto :eof
