@echo off
chcp 65001 >nul 2>&1
title WordBook Launcher

echo.
echo ============================================
echo   WordBook App - Smart Startup v4.6
echo ============================================
echo.

echo [1/6] Killing old WordBook processes...
taskkill /F /FI "WINDOWTITLE eq WordBook Backend*" >nul 2>&1
taskkill /F /FI "WINDOWTITLE eq WordBook Frontend*" >nul 2>&1
timeout /t 2 /nobreak >nul
echo [1/6] Done
echo.

echo [2/6] Cleaning Python cache...
for /d /r "D:\wordbook_app\backend" %%d in (__pycache__) do (
    if exist "%%d" rd /s /q "%%d" >nul 2>&1
)
echo [2/6] Done
echo.

echo [3/6] Finding free port for backend...
setlocal enabledelayedexpansion
set BACKEND_PORT=0
for %%p in (8000 8001 8080 9000 9001 9090 7000 7001 5000 5001 6000 6001) do (
    if !BACKEND_PORT!==0 (
        netstat -ano 2>nul | findstr "LISTENING" | findstr ":%%p " >nul 2>&1
        if errorlevel 1 (
            set BACKEND_PORT=%%p
        )
    )
)
if !BACKEND_PORT!==0 (
    echo   ERROR: No free port found!
    goto :end
)
echo   Found free port: !BACKEND_PORT!
echo [3/6] Done
echo.

echo [4/6] Patching frontend API URL to port !BACKEND_PORT!...
set THEME_FILE=D:\wordbook_app\flutter_app\lib\core\theme.dart

REM Use PowerShell to do reliable text replacement
powershell -Command "(Get-Content '%THEME_FILE%') -replace 'http://localhost:\d+/api/v1', 'http://localhost:!BACKEND_PORT!/api/v1' | Set-Content '%THEME_FILE%' -Encoding UTF8"

REM Verify
findstr "localhost:!BACKEND_PORT!" "%THEME_FILE%" >nul 2>&1
if %errorlevel%==0 (
    echo   theme.dart patched to port !BACKEND_PORT! OK
) else (
    echo   WARNING: patch may have failed, check theme.dart
)
echo [4/6] Done
echo.

echo [5/6] Starting backend on port !BACKEND_PORT!...
start "WordBook Backend" cmd /k "title WordBook Backend && cd /d D:\wordbook_app\backend && call venv\Scripts\activate && python -m uvicorn app.main:app --host 127.0.0.1 --port !BACKEND_PORT! --log-level info"

echo   Waiting for backend...
set attempts=0
:wait_loop
timeout /t 1 /nobreak >nul
set /a attempts+=1
curl -s http://localhost:!BACKEND_PORT!/ping 2>nul | findstr "pong" >nul 2>&1
if %errorlevel%==0 (
    echo   Backend ready in !attempts!s on port !BACKEND_PORT!
    curl -s http://localhost:!BACKEND_PORT!/ping 2>nul
    echo.
    goto :backend_ok
)
if !attempts! geq 20 (
    echo   Timeout. Check backend window for errors.
    goto :backend_ok
)
goto :wait_loop
:backend_ok
echo [5/6] Done
echo.

echo [6/6] Starting frontend + admin...
cd /d D:\wordbook_app\flutter_app
call flutter pub get
start "WordBook Frontend" cmd /k "title WordBook Frontend && cd /d D:\wordbook_app\flutter_app && flutter run -d chrome --web-port 3000"

timeout /t 8 /nobreak >nul
start "" "http://localhost:!BACKEND_PORT!/admin"
echo [6/6] Done
echo.

echo ============================================
echo   All started!
echo   Backend:  http://localhost:!BACKEND_PORT!
echo   Admin:    http://localhost:!BACKEND_PORT!/admin
echo   Frontend: http://localhost:3000
echo   API Docs: http://localhost:!BACKEND_PORT!/docs
echo ============================================

endlocal

:end
echo.
pause
