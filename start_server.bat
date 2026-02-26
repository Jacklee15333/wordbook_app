@echo off
echo =========================================================
echo   Wordbook App - Starting Server
echo =========================================================
echo.

cd /d "%~dp0backend"
echo Working directory: %cd%
echo.

if not exist "venv\Scripts\activate.bat" (
    echo [ERROR] Virtual environment not found!
    echo         Please run setup.bat first.
    pause
    exit /b 1
)

call venv\Scripts\activate.bat

echo Starting FastAPI backend server...
echo.
echo   API docs:  http://localhost:8000/docs
echo   Health:    http://localhost:8000/health
echo.
echo   Press Ctrl+C to stop
echo.

uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
pause
