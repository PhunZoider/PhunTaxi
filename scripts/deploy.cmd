@echo off
setlocal enabledelayedexpansion

rem ---------------------------------------------------------------------------
rem PhunSpawn deploy. Called by .vscode/settings.json on every save
rem (emeraldwalk.runonsave).
rem
rem Deploys to:
rem   %USERPROFILE%\Zomboid\mods\PhunSpawn              - playable
rem   %USERPROFILE%\Zomboid\mods\PhunSpawnTest          - test-id variant
rem   %USERPROFILE%\Zomboid\Workshop\PhunSpawn          - upload staging
rem   %USERPROFILE%\Zomboid\Workshop\PhunSpawnTest      - test upload staging
rem ---------------------------------------------------------------------------

set MODS=PhunSpawn

set SRC=%~dp0
set MODDIR=%USERPROFILE%\Zomboid\mods
set WS=%USERPROFILE%\Zomboid\Workshop\PhunSpawn
set WSTEST=%USERPROFILE%\Zomboid\Workshop\PhunSpawnTest

echo [PhunSpawn] Deploying to %MODDIR%

rem --- Live mods -------------------------------------------------------------
rem xclude applies HERE, and this is the only line where it can. The Workshop
rem staging copies below pass it too, but they then throw their Contents folder
rem away and take it from %MODDIR%, so a file not filtered on this line ships
rem in all four trees.
rem
rem xcopy matches each entry as a SUBSTRING of the whole source path, so keep
rem them specific. A bare extension is fine; a bare folder name is not.
for %%M in (%MODS%) do (
    rmdir /S /Q "%MODDIR%\%%M" 2>nul
    xcopy "%SRC%Contents\mods\%%M" "%MODDIR%\%%M" /Y /I /E /F /Q /EXCLUDE:%SRC%xclude >nul
    if errorlevel 1 echo [PhunSpawn] FAILED copying %%M
)

rem --- Test-id variants ------------------------------------------------------
rem Copy the live mod, then overlay Tests\root\<Mod>, which swaps in a mod.info
rem carrying the test id. Lets both versions sit side by side in one install.
rem
rem Neither copy here takes /EXCLUDE. The first does not need it, because
rem %MODDIR%\<Mod> was already filtered above. The second must NOT have it: its
rem source path contains "Tests", which is an xclude entry, so the substring
rem match would hit every file and the overlay would copy nothing at all.
for %%M in (%MODS%) do (
    rmdir /S /Q "%MODDIR%\%%MTest" 2>nul
    xcopy "%MODDIR%\%%M" "%MODDIR%\%%MTest" /Y /I /E /F /Q >nul
    if exist "%SRC%Tests\root\%%M" (
        xcopy "%SRC%Tests\root\%%M" "%MODDIR%\%%MTest" /Y /I /E /F /Q >nul
    )
)

rem --- Workshop staging, live ------------------------------------------------
rmdir /S /Q "%WS%" 2>nul
xcopy "%SRC%" "%WS%" /Y /I /E /F /Q /EXCLUDE:%SRC%xclude >nul
rmdir /S /Q "%WS%\Tests" 2>nul
rmdir /S /Q "%WS%\Contents" 2>nul
for %%M in (%MODS%) do (
    xcopy "%MODDIR%\%%M" "%WS%\Contents\mods\%%M" /Y /I /E /F /Q >nul
)

rem --- Workshop staging, test ------------------------------------------------
rem Same mod folder names as live, but each carries the test mod.info, and the
rem workshop.txt / preview.png come from Tests\.
rmdir /S /Q "%WSTEST%" 2>nul
xcopy "%SRC%" "%WSTEST%" /Y /I /E /F /Q /EXCLUDE:%SRC%xclude >nul
rmdir /S /Q "%WSTEST%\Tests" 2>nul
rmdir /S /Q "%WSTEST%\Contents" 2>nul
for %%M in (%MODS%) do (
    xcopy "%MODDIR%\%%MTest" "%WSTEST%\Contents\mods\%%M" /Y /I /E /F /Q >nul
)
copy /Y "%SRC%Tests\workshop.txt" "%WSTEST%\workshop.txt" >nul
if exist "%SRC%Tests\preview.png" copy /Y "%SRC%Tests\preview.png" "%WSTEST%\preview.png" >nul

echo [PhunSpawn] Done.
endlocal
