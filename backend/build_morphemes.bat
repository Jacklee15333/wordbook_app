@echo off
chcp 65001 >nul 2>&1
title MorphoLex - Build Morpheme Data
cd /d D:\wordbook_app\backend

echo.
echo ============================================================
echo   MorphoLex Morpheme Builder
echo ============================================================
echo.

:: Activate venv FIRST
if exist "venv\Scripts\activate.bat" (
    call venv\Scripts\activate.bat
    echo   [OK] Python venv activated
) else (
    echo   [WARN] No venv found
)

:: Install dependencies INSIDE venv
echo   Installing dependencies...
python -m pip install setuptools --quiet --disable-pip-version-check 2>nul
python -m pip install pronouncing --quiet --disable-pip-version-check 2>nul
python -m pip install morphemes --quiet --disable-pip-version-check 2>nul
echo   [OK] Dependencies ready

echo.
echo   Starting builder...
echo.
python build_morphemes_from_morpholex.py

echo.
echo ============================================================
echo   Done! Restart start_app.bat to see changes.
echo ============================================================
pause
