@echo off
echo =========================================================
echo   WordBook App - Flutter Frontend Setup
echo =========================================================
echo.

REM Check Flutter
flutter --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Flutter not found in PATH
    pause
    exit /b 1
)
echo [OK] Flutter found

REM Create Flutter project
echo.
echo [SETUP] Creating Flutter project...
cd /d D:\wordbook_app
if exist "frontend" (
    echo [OK] frontend directory already exists, skipping create
) else (
    flutter create --org com.wordbook --project-name wordbook_app frontend
    echo [OK] Flutter project created
)

REM Copy our files over
echo.
echo [SETUP] Copying source files...

REM Copy pubspec.yaml
copy /Y "%~dp0pubspec.yaml" "D:\wordbook_app\frontend\pubspec.yaml" >nul

REM Copy lib directory
xcopy /E /Y /I "%~dp0lib" "D:\wordbook_app\frontend\lib" >nul

REM Copy web/index.html
copy /Y "%~dp0web\index.html" "D:\wordbook_app\frontend\web\index.html" >nul

echo [OK] Source files copied

REM Get dependencies
echo.
echo [SETUP] Getting Flutter dependencies...
cd /d D:\wordbook_app\frontend
flutter pub get

echo.
echo =========================================================
echo   Setup complete!
echo =========================================================
echo.
echo   To run the app:
echo     cd D:\wordbook_app\frontend
echo     flutter run -d chrome
echo.
echo   Make sure the backend is running on port 8000 first!
echo.
pause
