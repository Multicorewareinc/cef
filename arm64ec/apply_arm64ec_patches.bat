@echo off
rem ===========================================================================
rem  Apply the CEF ARM64EC patches for Chromium 104.0.5112.102 / CEF 5112.
rem
rem  Usage:
rem    apply_arm64ec_patches.bat check  [chromium\src dir]   dry run
rem    apply_arm64ec_patches.bat apply  [chromium\src dir]   apply patches
rem    apply_arm64ec_patches.bat revert [chromium\src dir]   undo patches
rem
rem  The src dir defaults to the chromium\src that contains this checkout
rem  (this script lives in chromium\src\cef\arm64ec).
rem
rem  Run this AFTER automate-git.py has checked out Chromium and CEF has applied
rem  its own patches (see README.md). The CEF-side ARM64EC changes are commits
rem  on this branch; these patches cover Chromium, V8 and third-party repos.
rem  Patches that are already applied are detected and skipped, so the script
rem  is safe to run more than once.
rem  Note: depot_tools' git is git.bat, so every git call must use CALL.
rem ===========================================================================
setlocal EnableExtensions EnableDelayedExpansion

set "MODE=%~1"
set "SRC=%~2"
if "%SRC%"=="" for %%I in ("%~dp0..\..") do set "SRC=%%~fI"
set "PDIR=%~dp0patches\"
set "LIST=%PDIR%patches.txt"
set "LOG=%TEMP%\arm64ec_patch_%MODE%.log"

if /i not "%MODE%"=="check" if /i not "%MODE%"=="apply" if /i not "%MODE%"=="revert" (
  echo Usage: %~nx0 check^|apply^|revert [chromium\src dir]
  exit /b 1
)
where git >nul 2>&1 || (
  echo git was not found. Run: set PATH=C:\code\depot_tools;%%PATH%%
  exit /b 1
)
if not exist "%SRC%\cef\patch\patch.cfg" (
  echo "%SRC%" does not look like a CEF chromium\src checkout.
  exit /b 1
)

set /a OK=0
set /a SKIP=0
set /a FAIL=0
echo ARM64EC patch %MODE% - %DATE% %TIME% > "%LOG%"
echo Mode: %MODE%   Source: %SRC%
echo.

for /f "usebackq eol=# tokens=1,2" %%a in ("%LIST%") do (
  set "REL=%%a"
  set "REL=!REL:/=\!"
  if "!REL!"=="." (set "DIR=%SRC%") else (set "DIR=%SRC%\!REL!")
  call :patch "!DIR!" "%PDIR%%%b" "%%a"
)

echo.
echo ===========================================================
if /i "%MODE%"=="revert" (
  echo  Reverted: %OK%   Not applied: %SKIP%   Failed: %FAIL%
) else (
  echo  OK: %OK%   Already applied: %SKIP%   Failed: %FAIL%
)
echo  Log: %LOG%
echo ===========================================================
if %FAIL% GTR 0 exit /b 1
exit /b 0


rem ---------------------------------------------------------------------------
rem  :patch <repo dir> <patch file> <repo name>
rem ---------------------------------------------------------------------------
:patch
set "D=%~1"
set "P=%~2"
set "N=%~3"
if not exist "%P%" (
  call :report FAIL "%N%" "patch file not found: %P%"
  goto :eof
)
if not exist "%D%\" (
  call :report FAIL "%N%" "directory not found: %D%"
  goto :eof
)
pushd "%D%"

if /i "%MODE%"=="revert" goto :patch_revert

call git apply --check "%P%" >nul 2>&1
if errorlevel 1 goto :patch_not_clean
if /i "%MODE%"=="check" (
  call :report OK "%N%" "can be applied"
  popd & goto :eof
)
echo ---- applying %~nx2 in %N% >>"%LOG%"
call git apply -v "%P%" >>"%LOG%" 2>&1
if errorlevel 1 (call :report FAIL "%N%" "git apply failed - see log") else (call :report OK "%N%" "applied")
popd & goto :eof

:patch_not_clean
call git apply --check -R "%P%" >nul 2>&1
if errorlevel 1 (
  echo ---- %~nx2 does not apply in %N% >>"%LOG%"
  call git apply --check -v "%P%" >>"%LOG%" 2>&1
  call :report FAIL "%N%" "does not apply cleanly - see log"
) else (
  call :report SKIP "%N%" "already applied"
)
popd & goto :eof

:patch_revert
call git apply --check -R "%P%" >nul 2>&1
if errorlevel 1 (
  call :report SKIP "%N%" "not applied, nothing to revert"
  popd & goto :eof
)
echo ---- reverting %~nx2 in %N% >>"%LOG%"
call git apply -R -v "%P%" >>"%LOG%" 2>&1
if errorlevel 1 (call :report FAIL "%N%" "revert failed - see log") else (call :report OK "%N%" "reverted")
popd & goto :eof


:report
if "%~1"=="OK"   set /a OK+=1
if "%~1"=="SKIP" set /a SKIP+=1
if "%~1"=="FAIL" set /a FAIL+=1
echo [%~1] %~2 - %~3
echo [%~1] %~2 - %~3 >>"%LOG%"
goto :eof
