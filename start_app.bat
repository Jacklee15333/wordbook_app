@echo off
title WordBook App Launcher
echo ============================================
echo   WordBook App - 一键启动
echo ============================================
echo.

:: 启动后端 (新窗口)
echo [1/2] 正在启动后端服务...
start "WordBook Backend" cmd /k "cd /d D:\wordbook_app\backend && call venv\Scripts\activate && echo 后端启动中... && uvicorn app.main:app --reload --port 8000"

:: 等待后端启动
echo 等待后端启动 (3秒)...
timeout /t 3 /nobreak > nul

:: 启动前端 (新窗口)
echo [2/2] 正在启动前端...
start "WordBook Frontend" cmd /k "cd /d D:\wordbook_app\frontend && echo 前端启动中... && flutter run -d chrome"

echo.
echo ============================================
echo   全部启动完成！
echo   后端: http://localhost:8000/docs
echo   前端: 将在 Chrome 中自动打开
echo ============================================
echo.
echo 按任意键关闭此窗口...
pause > nul
