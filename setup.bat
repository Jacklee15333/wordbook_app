@echo off
echo =========================================================
echo   Wordbook App - Setup
echo =========================================================
echo.

REM --- Check Python ---
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python not found. Please install Python 3.10+
    pause
    exit /b 1
)
echo [OK] Python found

REM --- Go to backend directory ---
cd /d "%~dp0backend"
if errorlevel 1 (
    echo [ERROR] Cannot find backend directory at %~dp0backend
    pause
    exit /b 1
)
echo [OK] Backend directory: %cd%

REM --- Create venv ---
if not exist "venv" (
    echo.
    echo [SETUP] Creating Python virtual environment...
    python -m venv venv
    if errorlevel 1 (
        echo [ERROR] Failed to create venv
        pause
        exit /b 1
    )
    echo [OK] Virtual environment created
) else (
    echo [OK] Virtual environment already exists
)

REM --- Activate venv ---
call venv\Scripts\activate.bat

REM --- Install dependencies ---
echo.
echo [SETUP] Installing Python dependencies (may take a few minutes)...
pip install -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple
if errorlevel 1 (
    echo [WARN] Tsinghua mirror failed, trying default PyPI...
    pip install -r requirements.txt
)
echo [OK] Dependencies installed

REM --- Copy .env if not exists ---
if not exist ".env" (
    if exist ".env.example" (
        copy .env.example .env >nul
    )
    echo [OK] Created .env config file
) else (
    echo [OK] .env config already exists
)

REM --- Init database ---
echo.
echo [SETUP] Initializing database...
python -m scripts.init_db
if errorlevel 1 (
    echo.
    echo [ERROR] Database init failed! Check:
    echo   1. Is PostgreSQL service running?
    echo   2. Is the password in .env correct? Default: 123456
    echo   Tip: Win+R then services.msc to check PostgreSQL service
    pause
    exit /b 1
)

REM --- Create admin ---
echo.
echo [SETUP] Creating admin account...
python -m scripts.create_admin

echo.
echo =========================================================
echo   Setup complete!
echo =========================================================
echo.
echo   Admin: admin@wordbook.local / admin123
echo   Start server: run start_server.bat
echo.
pause
