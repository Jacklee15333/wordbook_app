@echo off
title WordBook Launcher

echo.
echo ============================================
echo   WordBook App - Smart Startup v5.0
echo ============================================
echo.

REM ============================================
REM  Config
REM ============================================
set APP_ROOT=D:\wordbook_app
set BACKEND_DIR=%APP_ROOT%\backend
set FRONTEND_DIR=%APP_ROOT%\flutter_app
set THEME_FILE=%FRONTEND_DIR%\lib\core\theme.dart
set UPDATES_DIR=%APP_ROOT%\updates

setlocal enabledelayedexpansion

REM ============================================
REM  [1/7] Kill old processes
REM ============================================
echo [1/7] Killing old WordBook processes...
taskkill /F /FI "WINDOWTITLE eq WordBook Backend*" >nul 2>&1
taskkill /F /FI "WINDOWTITLE eq WordBook Frontend*" >nul 2>&1
timeout /t 2 /nobreak >nul
echo   Done.
echo.

REM ============================================
REM  [2/7] Apply updates from updates/ folder
REM ============================================
echo [2/7] Checking updates folder...
set UPDATED=0
set DEPS_UPDATED=0
set UPDATE_LIST=

if not exist "%UPDATES_DIR%" (
    mkdir "%UPDATES_DIR%" >nul 2>&1
    echo   Created updates folder: %UPDATES_DIR%
    echo   No update files found.
    goto :update_done
)

REM --- Single files with known destinations ---

if exist "%UPDATES_DIR%\admin.html" (
    copy /Y "%UPDATES_DIR%\admin.html" "%BACKEND_DIR%\app\static\admin.html" >nul
    echo   [OK] admin.html  -^>  backend\app\static\admin.html
    set UPDATED=1
)

if exist "%UPDATES_DIR%\main.py" (
    copy /Y "%UPDATES_DIR%\main.py" "%BACKEND_DIR%\app\main.py" >nul
    echo   [OK] main.py  -^>  backend\app\main.py
    set UPDATED=1
)

if exist "%UPDATES_DIR%\media_service.py" (
    copy /Y "%UPDATES_DIR%\media_service.py" "%BACKEND_DIR%\app\services\media_service.py" >nul
    echo   [OK] media_service.py  -^>  backend\app\services\media_service.py
    set UPDATED=1
)

if exist "%UPDATES_DIR%\media.py" (
    copy /Y "%UPDATES_DIR%\media.py" "%BACKEND_DIR%\app\api\media.py" >nul
    echo   [OK] media.py  -^>  backend\app\api\media.py
    set UPDATED=1
)

if exist "%UPDATES_DIR%\admin.py" (
    copy /Y "%UPDATES_DIR%\admin.py" "%BACKEND_DIR%\app\api\admin.py" >nul
    echo   [OK] admin.py  -^>  backend\app\api\admin.py
    set UPDATED=1
)

if exist "%UPDATES_DIR%\config.py" (
    copy /Y "%UPDATES_DIR%\config.py" "%BACKEND_DIR%\app\core\config.py" >nul
    echo   [OK] config.py  -^>  backend\app\core\config.py
    set UPDATED=1
)

if exist "%UPDATES_DIR%\database.py" (
    copy /Y "%UPDATES_DIR%\database.py" "%BACKEND_DIR%\app\core\database.py" >nul
    echo   [OK] database.py  -^>  backend\app\core\database.py
    set UPDATED=1
)

if exist "%UPDATES_DIR%\init_db.py" (
    copy /Y "%UPDATES_DIR%\init_db.py" "%BACKEND_DIR%\scripts\init_db.py" >nul
    echo   [OK] init_db.py  -^>  backend\scripts\init_db.py
    set UPDATED=1
)

if exist "%UPDATES_DIR%\theme.dart" (
    copy /Y "%UPDATES_DIR%\theme.dart" "%FRONTEND_DIR%\lib\core\theme.dart" >nul
    echo   [OK] theme.dart  -^>  flutter_app\lib\core\theme.dart
    set UPDATED=1
)

if exist "%UPDATES_DIR%\api_service.dart" (
    copy /Y "%UPDATES_DIR%\api_service.dart" "%FRONTEND_DIR%\lib\services\api_service.dart" >nul
    echo   [OK] api_service.dart  -^>  flutter_app\lib\services\api_service.dart
    set UPDATED=1
)

if exist "%UPDATES_DIR%\home_screen.dart" (
    copy /Y "%UPDATES_DIR%\home_screen.dart" "%FRONTEND_DIR%\lib\screens\home\home_screen.dart" >nul
    echo   [OK] home_screen.dart  -^>  flutter_app\lib\screens\home\home_screen.dart
    set UPDATED=1
)

if exist "%UPDATES_DIR%\study_screen.dart" (
    copy /Y "%UPDATES_DIR%\study_screen.dart" "%FRONTEND_DIR%\lib\screens\study\study_screen.dart" >nul
    echo   [OK] study_screen.dart  -^>  flutter_app\lib\screens\study\study_screen.dart
    set UPDATED=1
)

if exist "%UPDATES_DIR%\study_provider.dart" (
    copy /Y "%UPDATES_DIR%\study_provider.dart" "%FRONTEND_DIR%\lib\providers\study_provider.dart" >nul
    echo   [OK] study_provider.dart  -^>  flutter_app\lib\providers\study_provider.dart
    set UPDATED=1
)

if exist "%UPDATES_DIR%\auth_provider.dart" (
    copy /Y "%UPDATES_DIR%\auth_provider.dart" "%FRONTEND_DIR%\lib\providers\auth_provider.dart" >nul
    echo   [OK] auth_provider.dart  -^>  flutter_app\lib\providers\auth_provider.dart
    set UPDATED=1
)

if exist "%UPDATES_DIR%\login_screen.dart" (
    copy /Y "%UPDATES_DIR%\login_screen.dart" "%FRONTEND_DIR%\lib\screens\auth\login_screen.dart" >nul
    echo   [OK] login_screen.dart  -^>  flutter_app\lib\screens\auth\login_screen.dart
    set UPDATED=1
)

if exist "%UPDATES_DIR%\wordbook_list_screen.dart" (
    copy /Y "%UPDATES_DIR%\wordbook_list_screen.dart" "%FRONTEND_DIR%\lib\screens\wordbook\wordbook_list_screen.dart" >nul
    echo   [OK] wordbook_list_screen.dart  -^>  flutter_app\lib\screens\wordbook\...
    set UPDATED=1
)

if exist "%UPDATES_DIR%\wordbook_detail_screen.dart" (
    copy /Y "%UPDATES_DIR%\wordbook_detail_screen.dart" "%FRONTEND_DIR%\lib\screens\wordbook\wordbook_detail_screen.dart" >nul
    echo   [OK] wordbook_detail_screen.dart  -^>  flutter_app\lib\screens\wordbook\...
    set UPDATED=1
)

if exist "%UPDATES_DIR%\import_words_dialog_v2.dart" (
    copy /Y "%UPDATES_DIR%\import_words_dialog_v2.dart" "%FRONTEND_DIR%\lib\import_words_dialog_v2.dart" >nul
    echo   [OK] import_words_dialog_v2.dart  -^>  flutter_app\lib\...
    set UPDATED=1
)

if exist "%UPDATES_DIR%\pubspec.yaml" (
    copy /Y "%UPDATES_DIR%\pubspec.yaml" "%FRONTEND_DIR%\pubspec.yaml" >nul
    echo   [OK] pubspec.yaml  -^>  flutter_app\pubspec.yaml
    set UPDATED=1
)

REM --- v5.0: backend model / schema / dependency files ---

if exist "%UPDATES_DIR%\word.py" (
    copy /Y "%UPDATES_DIR%\word.py" "%BACKEND_DIR%\app\models\word.py" >nul
    echo   [OK] word.py  -^>  backend\app\models\word.py
    set UPDATED=1
)

if exist "%UPDATES_DIR%\schemas__init__.py" (
    copy /Y "%UPDATES_DIR%\schemas__init__.py" "%BACKEND_DIR%\app\schemas\__init__.py" >nul
    echo   [OK] schemas__init__.py  -^>  backend\app\schemas\__init__.py
    set UPDATED=1
)

if exist "%UPDATES_DIR%\requirements.txt" (
    copy /Y "%UPDATES_DIR%\requirements.txt" "%BACKEND_DIR%\requirements.txt" >nul
    echo   [OK] requirements.txt  -^>  backend\requirements.txt
    set UPDATED=1
    set DEPS_UPDATED=1
)

if exist "%UPDATES_DIR%\fill_syllables.py" (
    copy /Y "%UPDATES_DIR%\fill_syllables.py" "%BACKEND_DIR%\fill_syllables.py" >nul
    echo   [OK] fill_syllables.py  -^>  backend\fill_syllables.py
    set UPDATED=1
)

if exist "%UPDATES_DIR%\study.py" (
    copy /Y "%UPDATES_DIR%\study.py" "%BACKEND_DIR%\app\api\study.py" >nul
    echo   [OK] study.py  -^>  backend\app\api\study.py
    set UPDATED=1
)

if exist "%UPDATES_DIR%\import_processor.py" (
    copy /Y "%UPDATES_DIR%\import_processor.py" "%BACKEND_DIR%\app\services\import_processor.py" >nul
    echo   [OK] import_processor.py  -^>  backend\app\services\import_processor.py
    set UPDATED=1
)

if exist "%UPDATES_DIR%\words.py" (
    copy /Y "%UPDATES_DIR%\words.py" "%BACKEND_DIR%\app\api\words.py" >nul
    echo   [OK] words.py  -^>  backend\app\api\words.py
    set UPDATED=1
)

if exist "%UPDATES_DIR%\word_media.py" (
    copy /Y "%UPDATES_DIR%\word_media.py" "%BACKEND_DIR%\app\models\word_media.py" >nul
    echo   [OK] word_media.py  -^>  backend\app\models\word_media.py
    set UPDATED=1
)

if exist "%UPDATES_DIR%\security.py" (
    copy /Y "%UPDATES_DIR%\security.py" "%BACKEND_DIR%\app\core\security.py" >nul
    echo   [OK] security.py  -^>  backend\app\core\security.py
    set UPDATED=1
)

REM --- Directory structure copy (advanced) ---

if exist "%UPDATES_DIR%\backend" (
    xcopy /Y /E /Q "%UPDATES_DIR%\backend\*" "%BACKEND_DIR%\" >nul 2>&1
    echo   [OK] backend\ folder  -^>  backend\  (recursive copy)
    set UPDATED=1
)

if exist "%UPDATES_DIR%\flutter_app" (
    xcopy /Y /E /Q "%UPDATES_DIR%\flutter_app\*" "%FRONTEND_DIR%\" >nul 2>&1
    echo   [OK] flutter_app\ folder  -^>  flutter_app\  (recursive copy)
    set UPDATED=1
)

if !UPDATED!==0 (
    echo   No update files found.
)
echo.

:update_done

REM ============================================
REM  [3/7] Clean Python cache
REM ============================================
echo [3/7] Cleaning Python cache...
for /d /r "%BACKEND_DIR%" %%d in (__pycache__) do (
    if exist "%%d" rd /s /q "%%d" >nul 2>&1
)
echo   Done.
echo.

REM ============================================
REM  [4/7] Find free port
REM ============================================
echo [4/7] Finding free port...
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
echo.

REM ============================================
REM  [5/7] Patch frontend API URL
REM ============================================
echo [5/7] Patching frontend API URL to port !BACKEND_PORT!...
powershell -Command "$f='%THEME_FILE%'; $c=[System.IO.File]::ReadAllText($f); $c=$c -replace 'http://localhost:\d+/api/v1','http://localhost:!BACKEND_PORT!/api/v1'; [System.IO.File]::WriteAllText($f,$c,[System.Text.Encoding]::UTF8)"

findstr "localhost:!BACKEND_PORT!" "%THEME_FILE%" >nul 2>&1
if %errorlevel%==0 (
    echo   theme.dart patched OK
) else (
    echo   WARNING: patch may have failed
)
echo.

REM ============================================
REM  [6/7] Start backend
REM ============================================
echo [6/7] Starting backend...
cd /d %BACKEND_DIR%
call venv\Scripts\activate

REM --- Check and install all pip dependencies ---
echo   Checking Python dependencies...
if !DEPS_UPDATED!==1 (
    echo   requirements.txt updated, installing all dependencies...
    pip install -r requirements.txt >nul 2>&1
    echo   Dependencies installed from requirements.txt.
) else (
    REM Quick check: verify a few key packages are present
    set NEED_INSTALL=0
    pip show pyphen >nul 2>&1
    if errorlevel 1 set NEED_INSTALL=1
    pip show eng-to-ipa >nul 2>&1
    if errorlevel 1 set NEED_INSTALL=1
    pip show fastapi >nul 2>&1
    if errorlevel 1 set NEED_INSTALL=1

    if !NEED_INSTALL!==1 (
        echo   Some packages missing, installing from requirements.txt...
        pip install -r requirements.txt >nul 2>&1
        pip install eng-to-ipa >nul 2>&1
        echo   Dependencies installed.
    ) else (
        echo   All dependencies OK.
    )
)

REM --- Also ensure eng-to-ipa (not in requirements.txt) ---
pip show eng-to-ipa >nul 2>&1
if errorlevel 1 (
    echo   Installing eng-to-ipa...
    pip install eng-to-ipa >nul 2>&1
)

start "WordBook Backend" cmd /k "title WordBook Backend && cd /d %BACKEND_DIR% && call venv\Scripts\activate && python -m uvicorn app.main:app --host 127.0.0.1 --port !BACKEND_PORT! --log-level info"

echo   Waiting for backend...
set attempts=0
:wait_loop
timeout /t 1 /nobreak >nul
set /a attempts+=1
curl -s http://localhost:!BACKEND_PORT!/ping 2>nul | findstr "pong" >nul 2>&1
if %errorlevel%==0 (
    echo   Backend ready in !attempts!s on port !BACKEND_PORT!
    goto :backend_ok
)
if !attempts! geq 30 (
    echo   Timeout - check backend window for errors.
    goto :backend_ok
)
goto :wait_loop
:backend_ok
echo.

REM ============================================
REM  [6.5/7] Auto-fix missing phonetics
REM ============================================
echo [6.5/7] Auto-fixing missing phonetics...
curl -s -X POST http://localhost:!BACKEND_PORT!/api/v1/admin/fix-phonetics >nul 2>&1
echo   Phonetics fix triggered (runs in background).
echo.

REM ============================================
REM  [7/7] Start frontend
REM ============================================
echo [7/7] Starting frontend...
cd /d %FRONTEND_DIR%

if not exist "%FRONTEND_DIR%\.dart_tool" (
    echo   First run - installing dependencies...
    call flutter pub get
) else (
    echo   Dependencies OK, skipping pub get.
)

echo   Launching Flutter Web on port 3000...
start "WordBook Frontend" cmd /k "title WordBook Frontend && cd /d %FRONTEND_DIR% && flutter run -d chrome --web-port 3000 --web-renderer html"

echo   Waiting for frontend (may take a while)...
set fe_attempts=0
:fe_wait
timeout /t 3 /nobreak >nul
set /a fe_attempts+=1
curl -s -o nul -w "%%{http_code}" http://localhost:3000 2>nul | findstr "200" >nul 2>&1
if %errorlevel%==0 (
    echo   Frontend ready!
    goto :fe_ok
)
if !fe_attempts! geq 20 (
    echo   Frontend still compiling... (normal for first launch)
    goto :fe_ok
)
goto :fe_wait
:fe_ok
echo.

REM ============================================
REM  Open browser
REM ============================================
timeout /t 2 /nobreak >nul
start "" "http://localhost:!BACKEND_PORT!/admin"

echo.
echo ============================================
echo   All started!
echo   Backend:  http://localhost:!BACKEND_PORT!
echo   Admin:    http://localhost:!BACKEND_PORT!/admin
echo   Frontend: http://localhost:3000
echo   API Docs: http://localhost:!BACKEND_PORT!/docs
echo ============================================
echo.
echo   TIP: Press Ctrl+Shift+R in browser to
echo        force refresh if page looks old.
echo.

REM ============================================
REM  Ask to clean updates folder
REM ============================================
if !UPDATED!==1 (
    echo ============================================
    echo   Update files are still in:
    echo   %UPDATES_DIR%
    echo.
    echo   If everything works fine, you can clean
    echo   them up now. If not, keep them and restart.
    echo ============================================
    echo.
    set /p CLEAN_CHOICE="Clean updates folder? (Y=yes, N=keep): "
    if /i "!CLEAN_CHOICE!"=="Y" (
        echo   Cleaning updates folder...
        REM Delete files but keep the folder itself
        del /Q "%UPDATES_DIR%\*.html" >nul 2>&1
        del /Q "%UPDATES_DIR%\*.py" >nul 2>&1
        del /Q "%UPDATES_DIR%\*.dart" >nul 2>&1
        del /Q "%UPDATES_DIR%\*.yaml" >nul 2>&1
        del /Q "%UPDATES_DIR%\*.txt" >nul 2>&1
        if exist "%UPDATES_DIR%\backend" rd /s /q "%UPDATES_DIR%\backend" >nul 2>&1
        if exist "%UPDATES_DIR%\flutter_app" rd /s /q "%UPDATES_DIR%\flutter_app" >nul 2>&1
        echo   Done! Updates folder cleaned.
    ) else (
        echo   OK, keeping update files.
    )
    echo.
)

endlocal

:end
echo.
pause
