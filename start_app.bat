@echo off
title WordBook Launcher

echo.
echo ============================================
echo   WordBook App - Full Restart
echo ============================================
echo.

echo [1/5] Killing old processes...
taskkill /F /FI "WINDOWTITLE eq WordBook Backend*" >nul 2>&1
taskkill /F /FI "WINDOWTITLE eq WordBook Frontend*" >nul 2>&1
taskkill /F /IM uvicorn.exe >nul 2>&1
taskkill /F /IM dart.exe >nul 2>&1
for /f "tokens=5" %%a in ('netstat -ano 2^>nul ^| findstr ":8000 " ^| findstr "LISTENING"') do (
    echo   Killing PID=%%a on port 8000
    taskkill /F /PID %%a >nul 2>&1
)
timeout /t 2 /nobreak >nul
echo [1/5] Done
echo.

echo [2/5] Cleaning Python cache...
if not exist "D:\wordbook_app\backend" (
    echo ERROR: D:\wordbook_app\backend not found!
    goto :end
)
for /d /r "D:\wordbook_app\backend" %%d in (__pycache__) do (
    if exist "%%d" rd /s /q "%%d" >nul 2>&1
)
del /s /q "D:\wordbook_app\backend\*.pyc" >nul 2>&1
echo [2/5] Done
echo.

echo [3/5] Cleaning Flutter cache...
if not exist "D:\wordbook_app\flutter_app" (
    echo ERROR: D:\wordbook_app\flutter_app not found!
    goto :end
)
cd /d D:\wordbook_app\flutter_app
call flutter clean
if %errorlevel% neq 0 (
    echo ERROR: flutter clean failed! Is Flutter installed and in PATH?
    goto :end
)
call flutter pub get
if %errorlevel% neq 0 (
    echo ERROR: flutter pub get failed! Check pubspec.yaml or network.
    goto :end
)
echo [3/5] Done
echo.

echo [4/5] Starting backend...
start "WordBook Backend" cmd /k "title WordBook Backend && cd /d D:\wordbook_app\backend && call venv\Scripts\activate && uvicorn app.main:app --reload --port 8000 --log-level info"

echo   Waiting for backend (max 20s)...
set attempts=0
:wait_loop
timeout /t 1 /nobreak >nul
set /a attempts+=1
curl -s --max-time 1 http://localhost:8000/health >nul 2>&1
if %errorlevel%==0 ( echo [4/5] Backend ready in %attempts%s && goto :backend_ok )
if %attempts% geq 20 ( echo WARNING: Backend not responding, check backend window && goto :backend_ok )
goto :wait_loop
:backend_ok
echo.

echo [5/5] Starting frontend...
start "WordBook Frontend" cmd /k "title WordBook Frontend && cd /d D:\wordbook_app\flutter_app && flutter run -d chrome --web-port 3000"
echo [5/5] Done - Chrome will open shortly
echo.

echo ============================================
echo   All started!
echo   Backend:  http://localhost:8000
echo   API Docs: http://localhost:8000/docs
echo   Admin:    http://localhost:8000/admin
echo   Frontend: http://localhost:3000
echo ============================================

:end
echo.
echo Press any key to close this window...
pause >nul
