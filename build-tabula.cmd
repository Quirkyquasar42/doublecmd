@echo off
rem Builds the Tabula Double Commander (dark-mode Windows build) into this folder as doublecmd.exe.
rem Needs Lazarus 4.x. Set LAZARUS_HOME first if Lazarus is not in C:\lazarus.
cd /d "%~dp0"
if "%LAZARUS_HOME%"=="" set LAZARUS_HOME=C:\lazarus
if not exist "%LAZARUS_HOME%\lazbuild.exe" (
  echo Lazarus not found in %LAZARUS_HOME%. Set LAZARUS_HOME to your Lazarus folder and run this again.
  pause
  exit /b 1
)
echo Building with Lazarus in %LAZARUS_HOME% ... (10-20 minutes the first time)
call build.bat darkwin > build-tabula.log 2>&1
if exist doublecmd.exe (echo Done: %~dp0doublecmd.exe) else (echo BUILD FAILED - see build-tabula.log & findstr /C:"Error" build-tabula.log)
pause
