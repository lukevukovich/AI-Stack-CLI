@echo off
setlocal EnableExtensions EnableDelayedExpansion
title AI Stack CLI

REM ==================================================
REM                   AI Stack CLI
REM ==================================================

REM ---- Always run from the script folder ----
cd /d "%~dp0"

REM ---- Handle Ctrl+C as graceful shutdown ----
if not defined CTRL_C_HANDLER (
  set "CTRL_C_HANDLER=1"
  "%~f0" %*
  exit /b
)

REM ==================================================
REM Load .env file
REM ==================================================
if not exist ".env" (
  echo [ERROR] .env file not found in %CD%
  echo Create .env next to this .bat file.
  pause
  exit /b 1
)

for /f "usebackq tokens=1,* delims==" %%A in (".env") do (
  if not "%%A"=="" if not "%%A:~0,1%"=="#" (
    set "%%A=%%B"
  )
)

REM ==================================================
REM Required vars
REM ==================================================
set "REQUIRED_VARS=OPENWEBUI_EXE SEARX_SETTINGS_YML"
for %%V in (%REQUIRED_VARS%) do (
  if not defined %%V (
    echo [ERROR] Missing required env var: %%V
    pause
    exit /b 1
  )
)

REM ==================================================
REM Defaults (safe fallbacks)
REM ==================================================
if not defined TITLE_PREFIX set "TITLE_PREFIX=AI Stack"

if not defined OPENWEBUI_HOST set "OPENWEBUI_HOST=localhost"
if not defined OPENWEBUI_PORT set "OPENWEBUI_PORT=8080"

if not defined SEARX_HOST set "SEARX_HOST=localhost"
if not defined SEARX_HOST_PORT set "SEARX_HOST_PORT=8081"
if not defined SEARX_CONTAINER_PORT set "SEARX_CONTAINER_PORT=8080"

if not defined OLLAMA_HOST set "OLLAMA_HOST=localhost"
if not defined OLLAMA_PORT set "OLLAMA_PORT=11434"
if not defined OLLAMA_TAGS_PATH set "OLLAMA_TAGS_PATH=/api/tags"

if not defined SEARX_CONTAINER_NAME set "SEARX_CONTAINER_NAME=searxng"
if not defined SEARX_IMAGE set "SEARX_IMAGE=searxng/searxng"
if not defined SEARX_API_KEY set "SEARX_API_KEY=ai"
if not defined SEARX_SETTINGS_CONTAINER_PATH set "SEARX_SETTINGS_CONTAINER_PATH=/etc/searxng/settings.yml"

if not defined START_MINIMIZED set "START_MINIMIZED=1"
if not defined CLOSE_DOCKER_ON_QUIT set "CLOSE_DOCKER_ON_QUIT=1"
if not defined AUTO_OPEN_BROWSER_ON_BOOT set "AUTO_OPEN_BROWSER_ON_BOOT=0"
if not defined KILL_EXISTING_OLLAMA_ON_BOOT set "KILL_EXISTING_OLLAMA_ON_BOOT=1"

REM Boot readiness checks
if not defined WAIT_FOR_SERVICES_ON_BOOT set "WAIT_FOR_SERVICES_ON_BOOT=1"
if not defined DOCKER_TIMEOUT set "DOCKER_TIMEOUT=90"
if not defined OPENWEBUI_TIMEOUT set "OPENWEBUI_TIMEOUT=45"
if not defined SEARX_TIMEOUT set "SEARX_TIMEOUT=45"
if not defined OLLAMA_TIMEOUT set "OLLAMA_TIMEOUT=30"

REM Curl preference
if not defined PREFER_CURL set "PREFER_CURL=1"

REM ==================================================
REM Derived vars
REM ==================================================
set "OPENWEBUI_URL=http://%OPENWEBUI_HOST%:%OPENWEBUI_PORT%"
set "SEARX_URL=http://%SEARX_HOST%:%SEARX_HOST_PORT%"
set "OLLAMA_URL=http://%OLLAMA_HOST%:%OLLAMA_PORT%%OLLAMA_TAGS_PATH%"

set "W_OPENWEBUI=%TITLE_PREFIX% :: OpenWebUI"
set "W_OLLAMA=%TITLE_PREFIX% :: Ollama"
set "W_SEARXNG=%TITLE_PREFIX% :: SearXNG"

if "%START_MINIMIZED%"=="1" (set "MINFLAG=/min") else (set "MINFLAG=")

set "HAS_CURL=0"
where curl >nul 2>&1
if not errorlevel 1 set "HAS_CURL=1"
if "%PREFER_CURL%"=="1" if "%HAS_CURL%"=="0" set "HAS_CURL=0"

REM ==================================================
REM Start
REM ==================================================
cls
call :Banner
call :Log "Boot starting..."

call :Log "[1/6] Checking Docker..."
call :EnsureDocker || goto :FAIL

call :Log "[2/6] Starting Open WebUI..."
call :StartOpenWebUI

call :Log "[3/6] Starting Ollama..."
call :StartOllama

call :Log "[4/6] Starting SearXNG..."
call :StartSearxng

if "%WAIT_FOR_SERVICES_ON_BOOT%"=="1" (
  call :Log "[5/6] Waiting for services (best effort)..."
  call :WaitForUrl "%OPENWEBUI_URL%" %OPENWEBUI_TIMEOUT% "Open WebUI" || call :Log "[WARN] Open WebUI not reachable yet."
  call :WaitForUrl "%SEARX_URL%" %SEARX_TIMEOUT% "SearXNG" || call :Log "[WARN] SearXNG not reachable yet."
  call :WaitForOllama %OLLAMA_TIMEOUT% || call :Log "[WARN] Ollama API not reachable yet."
) else (
  call :Log "[5/6] Skipping service waits (WAIT_FOR_SERVICES_ON_BOOT=0)."
)

if "%AUTO_OPEN_BROWSER_ON_BOOT%"=="1" (
  call :Log "[ACTION] Auto-opening Open WebUI: %OPENWEBUI_URL%"
  start "" "%OPENWEBUI_URL%"
)

call :Log "[6/6] AI Stack loaded."
call :MenuHelp

REM ==================================================
REM Menu loop
REM ==================================================
:MENU
call :Log "Awaiting command... (O/S/L/M/Q)"
choice /c OSLMQ /n
set "SEL=%errorlevel%"

if "%SEL%"=="5" goto :SHUTDOWN
if "%SEL%"=="4" (call :MinimizeWindows & goto :MENU)
if "%SEL%"=="3" (call :RestoreWindows  & goto :MENU)
if "%SEL%"=="2" (call :Status          & goto :MENU)
if "%SEL%"=="1" (
  call :Log "[ACTION] Opening Open WebUI: %OPENWEBUI_URL%"
  start "" "%OPENWEBUI_URL%"
  call :Log "[OK] Browser launch requested."
  goto :MENU
)
goto :MENU

REM ==================================================
REM Shutdown
REM ==================================================
:SHUTDOWN
call :Log "[ACTION] Shutdown requested."
call :KillAll
call :Log "[DONE] AI Stack stopped."
timeout /t 2 >nul
exit /b 0

:FAIL
call :Log "[ERROR] Startup failed. Press any key to exit."
pause >nul
exit /b 1

REM ==================================================
REM Functions
REM ==================================================
:Banner
echo ==================================================
echo                   %TITLE_PREFIX% CLI
echo ==================================================
echo.
exit /b 0

:MenuHelp
call :Log "----------------------------------------------"
call :Log "Commands:"
call :Log "  O = Open WebUI in browser"
call :Log "  S = Status check"
call :Log "  L = Show logs (restore windows)"
call :Log "  M = Minimize logs"
call :Log "  Q = Quit (stop everything)"
call :Log "----------------------------------------------"
exit /b 0

:Log
set "TS=%DATE% %TIME:~0,8%"
echo [%TS%] %~1
exit /b 0

:EnsureDocker
docker info >nul 2>&1
if not errorlevel 1 (
  call :Log "[OK] Docker is running."
  exit /b 0
)

call :Log "[WARN] Docker not responding - starting Docker Desktop..."
docker desktop start >nul 2>&1

call :Log "[INFO] Waiting for Docker to become ready (timeout=%DOCKER_TIMEOUT%s)..."
call :WaitForDocker %DOCKER_TIMEOUT%
if errorlevel 1 (
  call :Log "[ERROR] Docker did not become ready."
  exit /b 1
)

call :Log "[OK] Docker is running."
exit /b 0

:WaitForDocker
set "MAX=%~1"
set /a MAX_NUM=0
set /a MAX_NUM=%MAX% 2>nul
if %MAX_NUM% LEQ 0 set /a MAX_NUM=90

for /l %%I in (1,1,%MAX_NUM%) do (
  docker info >nul 2>&1
  if not errorlevel 1 exit /b 0
  timeout /t 1 >nul 2>&1
)
exit /b 1

:StartOpenWebUI
start "%W_OPENWEBUI%" %MINFLAG% cmd.exe /k ""%OPENWEBUI_EXE%" serve"
call :Log "[OK] Open WebUI window launched (title: %W_OPENWEBUI%)."
exit /b 0

:StartOllama
if "%KILL_EXISTING_OLLAMA_ON_BOOT%"=="1" (
  start "%W_OLLAMA%" %MINFLAG% cmd.exe /k "taskkill /IM ollama.exe /F >nul 2>&1 & ollama serve"
) else (
  start "%W_OLLAMA%" %MINFLAG% cmd.exe /k "ollama serve"
)
call :Log "[OK] Ollama window launched (title: %W_OLLAMA%)."
exit /b 0

:StartSearxng
docker rm -f "%SEARX_CONTAINER_NAME%" >nul 2>&1
start "%W_SEARXNG%" %MINFLAG% cmd.exe /k ^
docker run --rm --name "%SEARX_CONTAINER_NAME%" -p %SEARX_HOST_PORT%:%SEARX_CONTAINER_PORT% -e SEARXNG_KEY=%SEARX_API_KEY% -v "%SEARX_SETTINGS_YML%:%SEARX_SETTINGS_CONTAINER_PATH%" "%SEARX_IMAGE%"
call :Log "[OK] SearXNG window launched (title: %W_SEARXNG%)."
exit /b 0

:WaitForUrl
set "URL=%~1"
set "MAX=%~2"
set "LABEL=%~3"

set /a MAX_NUM=0
set /a MAX_NUM=%MAX% 2>nul
if %MAX_NUM% LEQ 0 set /a MAX_NUM=30

call :Log "[INFO] Waiting for %LABEL% (%URL%) up to %MAX_NUM%s..."

for /l %%I in (1,1,%MAX_NUM%) do (
  if "%HAS_CURL%"=="1" (
    curl -s -I --max-time 2 "%URL%" >nul 2>&1
  ) else (
    powershell -NoProfile -Command "try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 '%URL%' | Out-Null; exit 0 } catch { exit 1 }" >nul 2>&1
  )

  if not errorlevel 1 (
    call :Log "[OK] %LABEL% reachable."
    exit /b 0
  )

  timeout /t 1 >nul 2>&1
)

echo.
call :Log "[WARN] %LABEL% not reachable after %MAX_NUM%s."
exit /b 1

:WaitForOllama
set "MAX=%~1"
set /a MAX_NUM=0
set /a MAX_NUM=%MAX% 2>nul
if %MAX_NUM% LEQ 0 set /a MAX_NUM=30

call :Log "[INFO] Waiting for Ollama API (%OLLAMA_URL%) up to %MAX_NUM%s..."

for /l %%I in (1,1,%MAX_NUM%) do (
  if "%HAS_CURL%"=="1" (
    curl -s --max-time 2 "%OLLAMA_URL%" >nul 2>&1
  ) else (
    powershell -NoProfile -Command "try { Invoke-RestMethod -TimeoutSec 2 '%OLLAMA_URL%' | Out-Null; exit 0 } catch { exit 1 }" >nul 2>&1
  )

  if not errorlevel 1 (
    call :Log "[OK] Ollama API reachable."
    exit /b 0
  )

  timeout /t 1 >nul 2>&1
)

echo.
call :Log "[WARN] Ollama API not reachable after %MAX_NUM%s."
exit /b 1

:Status
call :Log "------------------- STATUS -------------------"
docker info >nul 2>&1
if errorlevel 1 (call :Log "Docker:   DOWN") else (call :Log "Docker:   UP")

call :QuickUrl "%OPENWEBUI_URL%" "OpenWebUI"
call :QuickUrl "%SEARX_URL%" "SearXNG"
call :QuickUrl "%OLLAMA_URL%" "Ollama"

for /f "delims=" %%A in ('docker ps --filter "name=%SEARX_CONTAINER_NAME%" --format "{{.Names}}" 2^>nul') do set "SEARX_RUNNING=%%A"
if defined SEARX_RUNNING (
  call :Log "Container: %SEARX_CONTAINER_NAME% running"
) else (
  call :Log "Container: %SEARX_CONTAINER_NAME% not running"
)
set "SEARX_RUNNING="
call :Log "----------------------------------------------"
exit /b 0

:QuickUrl
set "URL=%~1"
set "NAME=%~2"
if "%HAS_CURL%"=="1" (
  curl -s -I --max-time 2 "%URL%" >nul 2>&1
  if errorlevel 1 (call :Log "%NAME%:  DOWN") else (call :Log "%NAME%:  UP")
) else (
  powershell -NoProfile -Command "try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 '%URL%' | Out-Null; exit 0 } catch { exit 1 }" >nul 2>&1
  if errorlevel 1 (call :Log "%NAME%:  DOWN") else (call :Log "%NAME%:  UP")
)
exit /b 0

:MinimizeWindows
call :Log "[ACTION] Minimizing log windows..."
call :ShowWindowByTitle "%W_OPENWEBUI%" 2
call :ShowWindowByTitle "%W_OLLAMA%" 2
call :ShowWindowByTitle "%W_SEARXNG%" 2
call :Log "[OK] Log windows minimized."
exit /b 0

:RestoreWindows
call :Log "[ACTION] Restoring log windows..."
call :ShowWindowByTitle "%W_OPENWEBUI%" 9
call :ShowWindowByTitle "%W_OLLAMA%" 9
call :ShowWindowByTitle "%W_SEARXNG%" 9
call :Log "[OK] Log windows restored."
exit /b 0

:ShowWindowByTitle
set "TPREFIX=%~1"
set "MODE=%~2"
powershell -NoProfile -Command ^
  "$t='%TPREFIX%'; $m=%MODE%; " ^
  "$sig='[DllImport(\"user32.dll\")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'; " ^
  "Add-Type -MemberDefinition $sig -Name Win32Show -Namespace Win32 -ErrorAction SilentlyContinue | Out-Null; " ^
  "Get-Process | Where-Object { $_.MainWindowTitle -like ($t+'*') } | ForEach-Object { [Win32.Win32Show]::ShowWindowAsync($_.MainWindowHandle,$m) | Out-Null }" >nul 2>&1
exit /b 0

:KillAll
call :Log "[STOP] Stopping %SEARX_CONTAINER_NAME% container..."
docker rm -f "%SEARX_CONTAINER_NAME%" >nul 2>&1
call :Log "[OK] %SEARX_CONTAINER_NAME% stopped/removed (best effort)."

call :Log "[STOP] Closing service windows..."
taskkill /FI "WINDOWTITLE eq %W_SEARXNG%*" /T /F >nul 2>&1
taskkill /FI "WINDOWTITLE eq %W_OLLAMA%*" /T /F >nul 2>&1
taskkill /FI "WINDOWTITLE eq %W_OPENWEBUI%*" /T /F >nul 2>&1
call :Log "[OK] Service windows closed (best effort)."

call :Log "[STOP] Killing remaining processes (best effort)..."
taskkill /IM ollama.exe /F >nul 2>&1
taskkill /IM open-webui.exe /F >nul 2>&1
call :Log "[OK] Process cleanup done."

if "%CLOSE_DOCKER_ON_QUIT%"=="1" (
  call :Log "[STOP] Closing Docker Desktop (optional)..."
  docker desktop stop >nul 2>&1
  call :Log "[OK] Docker Desktop stop issued (best effort)."
)
exit /b 0