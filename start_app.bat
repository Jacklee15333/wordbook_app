@echo off
chcp 65001 >nul
title WordBook App Launcher
echo ============================================
echo   WordBook App - Start
echo ============================================
echo.

:: ===== Kill existing Flutter/Chrome debug processes =====
echo [0/3] Cleaning up old processes...
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":8000 " ^| findstr "LISTENING"') do (
    echo      Killing backend PID=%%a on port 8000...
    taskkill /F /PID %%a >nul 2>&1
)
taskkill /F /IM uvicorn.exe >nul 2>&1
timeout /t 1 /nobreak >nul
echo      Port 8000 is clear.
echo.

:: ===== Start backend =====
echo [1/3] Starting backend...
start "WordBook Backend" cmd /k "chcp 65001 >nul && cd /d D:\wordbook_app\backend && call venv\Scripts\activate && echo Backend starting... && uvicorn app.main:app --reload --port 8000"

echo      Waiting for backend (5 seconds)...
timeout /t 5 /nobreak >nul

:: ===== Open admin page in browser =====
echo      Opening admin dashboard...
start "" "http://localhost:8000/admin"

:: ===== Clean and start frontend =====
echo [2/3] Cleaning Flutter build cache...
cd /d D:\wordbook_app\flutter_app
call flutter clean >nul 2>&1
echo      Flutter cache cleared.
echo.

echo [3/3] Starting frontend (this takes ~30 seconds)...
start "WordBook Frontend" cmd /k "chcp 65001 >nul && cd /d D:\wordbook_app\flutter_app && echo Frontend starting... && flutter run -d chrome"

echo.
echo ============================================
echo   All started!
echo   Backend API: http://localhost:8000/docs
echo   Admin Panel: http://localhost:8000/admin
echo   Frontend:    Chrome will open automatically
echo ============================================
echo.
echo   NOTE: Frontend path = flutter_app (not frontend)
echo ============================================

:: Auto-close this launcher window after 5 seconds
timeout /t 5 /nobreak >nul
exit
