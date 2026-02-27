@echo off
chcp 65001 >nul
title WordBook App Launcher
echo ============================================
echo   WordBook App - Start
echo ============================================
echo.

:: ===== Kill any process on port 8000 =====
echo [0/2] Checking port 8000...
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":8000 " ^| findstr "LISTENING"') do (
    echo      Found process PID=%%a on port 8000, killing...
    taskkill /F /PID %%a >nul 2>&1
)
:: Also kill any lingering uvicorn just in case
taskkill /F /IM uvicorn.exe >nul 2>&1
timeout /t 1 /nobreak >nul
echo      Port 8000 is clear.
echo.

:: ===== Start backend =====
echo [1/2] Starting backend...
start "WordBook Backend" cmd /k "chcp 65001 >nul && cd /d D:\wordbook_app\backend && call venv\Scripts\activate && echo Backend starting... && uvicorn app.main:app --reload --port 8000"

echo      Waiting for backend (5 seconds)...
timeout /t 5 /nobreak >nul

:: ===== Start frontend =====
echo [2/2] Starting frontend...
start "WordBook Frontend" cmd /k "chcp 65001 >nul && cd /d D:\wordbook_app\frontend && echo Frontend starting... && flutter run -d chrome"

echo.
echo ============================================
echo   All started!
echo   Backend: http://localhost:8000/docs
echo   Admin:   http://localhost:8000/admin
echo   Frontend: Chrome will open automatically
echo ============================================

:: Auto-close this launcher window after 3 seconds
timeout /t 3 /nobreak >nul
exit