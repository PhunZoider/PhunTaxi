@echo off
setlocal enabledelayedexpansion

rem ---------------------------------------------------------------------------
rem PhunTaxi map iteration: export -> repo -> check -> deploy -> reset.
rem   setx PS_MAPSRC "D:\pz-dev\maps\pi5\lots_phunspawn"
rem   scripts\map.cmd                  sync, check, deploy, reset the test save
rem   scripts\map.cmd Sandbox\maptest  same, resetting that save instead
rem   scripts\map.cmd -                sync, check, deploy; reset nothing
rem
rem   PS_MAPSRC    the editor's export folder for THIS map. Never lots\ --
rem                that is PhunInteriors' PI_MAPSRC and its map.cmd copies the
rem                whole of it into that repo, so a cell exported there ships
rem                from the wrong mod.
rem   PS_TESTSAVE  a save under %USERPROFILE%\Zomboid\Saves, e.g.
rem                Sandbox\maptest, or an absolute path to one. Falls back to
rem                PI_TESTSAVE, since it is the same world being tested.
rem   PI_REPO      the PhunInteriors checkout. Defaults to ..\PhunInteriors.
rem  setx PI_REPO "D:\pz-dev\code\PhunInteriors"  
rem                The checks live there and are not duplicated here: our map
rem                shares its coordinate space, its tiledefs and its registry.
rem
rem Quit the world to the main menu first. The game writes every loaded chunk
rem back to the save on the way out, so a reset done mid-game is overwritten.
rem
rem RUN tighten.pl BEFORE EXPORTING, after any WorldEd session. It covers every
rem .pzw in the project folder, so one run from PhunInteriors does this map too.
rem This script runs it as well, but by then the lotpacks are written and it can
rem only repair the project for the next export.
rem ---------------------------------------------------------------------------

rem This file lives in scripts, one below the repo root. SRC is the root, with
rem a trailing backslash, and SELF the same without one.
for %%I in ("%~dp0..") do set "SRC=%%~fI\"
set SELF=%SRC:~0,-1%
set MAPS=%SRC%Contents\mods\PhunTaxi\common\media\maps\phuntaxi
if not defined PI_REPO set PI_REPO=%SRC%..\PhunInteriors
pushd "%SRC%"

rem --- Sync ------------------------------------------------------------------
rem Copy, never mirror. map.info lives only in the repo -- the editor does not
rem export one, and a map without it is never registered -- so /MIR would
rem delete the one file the map cannot load without.
if not defined PS_MAPSRC (
    echo [map] PS_MAPSRC not set, skipping sync
) else if not exist "%PS_MAPSRC%\*.lotheader" (
    echo [map] no lotheaders in %PS_MAPSRC%, skipping sync
) else (
    robocopy "%PS_MAPSRC%" "%MAPS%" /XF map.info /NJH /NJS /NDL /NP
    if errorlevel 8 (
        echo [map] FAILED copying from %PS_MAPSRC%
        popd & exit /b 1
    )
)

rem --- Check -----------------------------------------------------------------
rem A mismatch warns rather than stops: mid-rework the map legitimately moves
rem ahead of the registry, and seeing it in game is the point of deploying.
rem perl ships with Git but only Git Bash puts it on PATH; a VS Code task or a
rem shortcut gets the Windows one.
set PERL=
for /f "delims=" %%P in ('where perl 2^>nul') do if not defined PERL set PERL=%%P
if not defined PERL if exist "%ProgramFiles%\Git\usr\bin\perl.exe" set PERL=%ProgramFiles%\Git\usr\bin\perl.exe
if not defined HOME set HOME=%USERPROFILE%

if not defined PERL (
    echo [map] *** perl not found, checks NOT run ***
) else if not exist "%PI_REPO%\scripts\roomcheck.pl" (
    echo [map] *** no PhunInteriors checkout at %PI_REPO%, checks NOT run ***
) else (
    pushd "%PI_REPO%"

    rem roomcheck runs from THERE and is told about us, because the registry it
    rem compares against is PhunInteriors' own: our rooms are registered into
    rem it by our interiors.lua. Checking our map without their lua reports
    rem every interior square as claimed by nobody, and checking it without
    rem their MAP reports all 990 of their slots as sitting on nothing.
    "!PERL!" scripts\roomcheck.pl --mod "%SELF%"
    if errorlevel 1 echo [map] *** roomcheck FAILED -- the registry does not match this map ***

    rem The border fence, read out of the lotpack that just landed. A gap here
    rem is a hole a zombie walks through and it is invisible from the editor.
    rem The perimeter is derived from the cells present, so this needs no
    rem per-map configuration.
    rem Guarded on there being a map at all, because fencecheck exits non-zero
    rem for an empty folder too and "gaps in the border fence" is the wrong
    rem thing to say about a map nobody has exported yet.
    if not exist "%MAPS%\*.lotpack" (
        echo [map] no lotpacks in the repo yet, skipping fencecheck
    ) else (
        "!PERL!" scripts\fencecheck.pl "%MAPS%" >nul 2>&1
        if errorlevel 1 (
            echo [map] *** fencecheck FAILED -- gaps in the border fence ***
            "!PERL!" scripts\fencecheck.pl "%MAPS%" 2>nul | findstr /C:"gap" /C:"turns" /C:"cells,"
        )
    )

    rem WorldEd rewrites every border lot rect to the building PLUS ONE on save,
    rem and that extra square blanks the neighbouring cell's first wall. This
    rem runs AFTER the export, so it repairs the project for the NEXT one and a
    rem non-zero exit is the news that this export was built from spilled rects.
    if defined PS_MAPSRC for %%D in ("%PS_MAPSRC%\..") do (
        "!PERL!" scripts\tighten.pl --detect "%%~fD"
        if errorlevel 2 echo [map] *** lot rects were spilled -- THIS export is stale, re-export and re-run ***
    )
    popd

    rem Zero zombie density is the whole point of an interior cell and nothing
    rem else checks it -- it is not a zone, it is a 1024 byte tail on the
    rem lotheader. zombies.pl always exits 0, so read the line it prints.
    for %%H in ("%MAPS%\*.lotheader") do (
        "!PERL!" "%PI_REPO%\scripts\zombies.pl" "%%H" | findstr /C:"all 1024 chunks zero" >nul
        if errorlevel 1 (
            echo [map] *** %%~nH has a NON-ZERO zombie density ***
            "!PERL!" "%PI_REPO%\scripts\zombies.pl" "%%H"
        )
    )
)

rem --- Deploy ----------------------------------------------------------------
call "%SRC%scripts\deploy.cmd"

rem --- Reset -----------------------------------------------------------------
set SAVE=%~1
if not defined SAVE set SAVE=%PS_TESTSAVE%
if not defined SAVE set SAVE=%PI_TESTSAVE%
if "%SAVE%"=="-" set SAVE=
if not defined SAVE (
    echo [map] no test save named, skipping reset
    popd & exit /b 0
)
if not exist "%SAVE%\map_ver.bin" set SAVE=%USERPROFILE%\Zomboid\Saves\%SAVE%
if not exist "%SAVE%\map_ver.bin" (
    echo [map] %SAVE% is not a save, refusing to delete anything in it
    popd & exit /b 1
)

rem Cells come from the lotheaders, so a cell added to the map is reset too.
for %%H in ("%MAPS%\*.lotheader") do set CELL_%%~nH=1

set N=0
for %%H in ("%MAPS%\*.lotheader") do (
    for %%F in (
        "%SAVE%\chunkdata\chunkdata_%%~nH.bin"
        "%SAVE%\metagrid\metacell_%%~nH.bin"
        "%SAVE%\apop\apop_%%~nH.bin"
        "%SAVE%\zpop\zpop_%%~nH.bin"
    ) do if exist %%F del /Q %%F & set /a N+=1
)

rem map\<chunkX>\<chunkY>.bin. A cell is 32 chunks (256 squares of 8).
if exist "%SAVE%\map" for /D %%D in ("%SAVE%\map\*") do (
    set /a CX=%%~nxD / 32
    for %%F in ("%%D\*.bin") do (
        set /a CY=%%~nF / 32
        if defined CELL_!CX!_!CY! del /Q "%%F" & set /a N+=1
    )
)

rem isoregiondata\datachunk_<chunkX>_<chunkY>.bin, the same chunk space as
rem map\ but flat rather than a directory per column. Left behind, the engine
rem keeps the room and region data it derived from the OLD chunk, so a room
rem whose shape changed in the editor comes back with its old regions -- which
rem reads as the export not having worked rather than as stale save data.
if exist "%SAVE%\isoregiondata" for %%F in ("%SAVE%\isoregiondata\datachunk_*.bin") do (
    for /f "tokens=2,3 delims=_" %%A in ("%%~nF") do (
        set /a CX=%%A / 32
        set /a CY=%%B / 32
        if defined CELL_!CX!_!CY! del /Q "%%F" & set /a N+=1
    )
)

rem Per-slot decor captures live here, in PhunInteriors' global mod data rather
rem than ours, because the rooms are registered into its registry. Kept, the
rem first scrub restores every room to the decor it had BEFORE the export --
rem which looks exactly like the export not having worked. This is a test save,
rem so every mod's goes.
if exist "%SAVE%\global_mod_data.bin" del /Q "%SAVE%\global_mod_data.bin" & set /a N+=1

echo [map] reset %SAVE%: deleted !N! files
popd
endlocal
