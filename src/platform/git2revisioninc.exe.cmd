@echo off

rem The output folder may arrive split at spaces (C:\GPT Review\...) or quoted: rebuild it from all arguments.
set "OUTDIR=%*"
set OUTDIR=%OUTDIR:"=%
rem no trailing backslash: before a closing quote it would escape it
if "%OUTDIR:~-1%"=="\" set "OUTDIR=%OUTDIR:~0,-1%"

if not exist "%OUTDIR%" ( md "%OUTDIR%" )

set REVISION_TXT="%OUTDIR%\revision.txt"
set REVISION_INC="%OUTDIR%\dcrevision.inc"

del /Q %REVISION_TXT% 2> nul
del /Q %REVISION_INC% 2> nul
copy ..\units\dcrevision.inc %REVISION_INC% > nul

git -C "%OUTDIR%" rev-list --count HEAD > %REVISION_TXT%

IF ERRORLEVEL 1 goto EXIT

set /P REVISION=<%REVISION_TXT%

echo %REVISION% | find "fatal:" > nul

IF NOT ERRORLEVEL 1 goto EXIT

git -C "%OUTDIR%" rev-parse --short HEAD > %REVISION_TXT%

IF ERRORLEVEL 1 goto EXIT

set /P COMMIT=<%REVISION_TXT%

echo // Created by Git2RevisionInc> %REVISION_INC%
echo const dcRevision = '%REVISION%';>> %REVISION_INC%
echo const dcCommit = '%COMMIT%';>> %REVISION_INC%

:EXIT

echo Git revision %REVISION% %COMMIT%