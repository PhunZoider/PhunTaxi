# The phuntaxi map

One cell, 87,49 -- world x 22272..22527, y 12544..12799. It was cell 87,49 of
PhunInteriors until 2026-09-20, when it was carved out so this mod could own
it. PhunInteriors no longer ships it, and it must not: maps sharing a `lots=`
chain share one coordinate space and `IsoLot.MapFiles` is ordered, so two maps
shipping 87,49 means the loser's cell is discarded with **no warning**.
`perl scripts/cells.pl` in the PhunInteriors repo is what checks that.

## Where it is built

`D:\pz-dev\maps\pi5\phuntaxi.pzw`, beside `phuninteriors.pzw`. Sharing that
folder is deliberate: `buildings/_` holds the border buildings and
`images/Floor_0_0.png` is the ground, so both are the same files PhunInteriors
uses rather than copies that can drift.

It exports to `lots_phuntaxi`, **never** to `lots`. That folder is
PhunInteriors' `PI_MAPSRC`, and its `map.cmd` robocopies the whole of it into
that repo, so a cell exported there would be shipped by the wrong mod.

Run `scripts\tighten.cmd` (or the VS Code task "Map: tighten lot rects") after
any WorldEd session and **before** exporting. PhunInteriors' own copy does the
same job. WorldEd rewrites every border lot rect to the
building plus one on save, and that extra square blanks the neighbouring
square's wall. It covers every `.pzw` in the folder, this one included.

## The border

Four lots and four posts, all from `buildings/_`:

| lot | where | what it walls |
|---|---|---|
| `Border_W` | x=0 | the west edge of column 0 |
| `Border_N` | y=0 | the north edge of row 0 |
| `Border_W` | x=255 | the west edge of column 255 |
| `Border_N` | y=255 | the north edge of row 255 |
| `Border_NW` x4 | the four corners | both faces, as one post sprite |

A wall blocks its own square's **west or north** edge, so lines 0 and 255 are
not symmetrical: the fence is inside line 0 and outside line 255, and the
enclosed ground is local 0..254 in both axes. The posts go **last** in the
cell, because each corner is claimed by a W lot and an N lot as well and the
last lot to claim a square is the one that writes it.

A lot writes its whole rect, blanks included, so the fence lines lose the
ground tile under them. That is what happens in PhunInteriors too and it does
not matter: those squares carry a wall and nobody stands on them.

## The tiles are PhunInteriors'

The ground is `phuninteriors_01_0` and the fence is `phuninteriors_01_8/9/10`.
This mod ships **no** tiledefs and no texture pack: they live in
PhunInteriors' `media/phuninteriors.tiles` and
`media/texturepacks/phuninteriors.pack`.

That is covered by `require=phuninteriors` in `mod.info`: PhunInteriors is a
hard dependency for the room and the rides as well, so the tiles are never
missing while this mod loads. If that ever stops being true, ship a copy of
those two files, or build a tileset of this mod's own, before it ships.

The taxi in the garage is PhunInteriors' too: `phuninteriors_02_0` to `_39`.
"Take taxi ride" is offered on any of those tiles, so the garage has to have
one placed where a new character can reach it. Nothing checks that it does.

The roller door on the garage's north wall is vanilla's `walls_garage_02_051`
to `_053`, painted as user tiles on the **Walls** layer of `spawn.tbx`, over a
wall object with `InteriorTrim="0"` in the garage's own wall tiles. Each part
of that is a fix, so keep all three:

- On the Walls layer it replaces the generated wall. On any other layer it is
  a second wall on the same edge, and Viewpoint draws both in one plane.
- No trim, or the room's wainscot is drawn over the bottom half of the door.
- Not `phuninteriors_01_009` behind it. PhunInteriors' Viewpoint pack draws
  that sprite with a black floor slab, which covered the concrete in 3D.

Those tiles are a real garage door, so the game makes them an IsoDoor.
`shared/PhunTaxi/garage_guard.lua` refuses opening it, and the office's back
door, which also opens onto the void: any shut door in the cell with a room
on one side only.

The south (y=28) and east (x=16) wall lines stand on squares no room claims,
so the exporter gives them the building's exterior wall, and Viewpoint draws
that one sprite on both faces. Each run carries an explicit wall object whose
`Tile` is a copy of the room's own interior set (entries 43 to 46, appended
so no index moves) and no trim, as PhunInteriors' `innerwalls.pl` does for
its rooms. That script skips `spawn.tbx`, so these were written by hand: a
room added or moved needs its runs redone.

## Power and water

One `NoPowerOrWater` zone over the whole cell, exported into
`lots_phuntaxi/objects.lua`:

```lua
{ name = "Waterless", type = "NoPowerOrWater",
  x = 22272, y = 12544, z = 0, width = 256, height = 256 }
```

`isNoPower()` compares zone types against the literal strings `"NoPower"` and
`"NoPowerOrWater"` and there is no Lua setter, so a zone is the only way to
take a square off the mains. `Zone.contains` is half open, so the width is the
cell size **exactly**, not one more. `IsoMetaGrid.registerZone` refuses
anything wider or taller than 1202, which 256 is comfortably under.

`isNoPower` calls `getZonesAt` with the level hardcoded to zero whatever level
the square is on, so this one z=0 rectangle covers z=1 as well.

## Zombies are not a zone

**There is no zone type that suppresses zombies.** Density is a 1024 byte tail
on the `.lotheader`, one byte per chunk, and it comes from the
`ZombieSpawnMap` image -- here `images/phuntaxi_ZombieSpawnMap.png`, a copy of
PhunInteriors' all black one, which is zero everywhere.

Verify it rather than assuming, after every export:

```bash
perl scripts/zombies.pl <this mod>/media/maps/phuntaxi/87_49.lotheader
#   all 1024 chunks zero -- nothing spawns here
```

(`zombies.pl` lives in the PhunInteriors repo.)

Two sandbox options bypass the whole layer and no map work survives either:
`Distribution = 2` (Uniform) substitutes a hardcoded 0.2 per chunk everywhere,
and `MinZombiesPerChunk` floors every chunk. Check the preset before blaming
the map.

A fence stops **pathing**, not realisation. A cell the game was never told the
density of is not zero, it was never set, so zombies can still be realised in
the void beyond the fence and walk in when a chunk loads. The answer is a ring
of empty cells that do ship a lotheader; there is not one yet.

## The loop

`scripts\map.cmd` is it: sync, check, deploy, reset. It is also the VS Code
task "Map: sync, check, deploy, reset".

```
setx PS_MAPSRC "D:\pz-dev\maps\pi5\lots_phuntaxi"
scripts\map.cmd                    sync, check, deploy, reset the test save
scripts\map.cmd Sandbox\maptest    same, resetting that save instead
scripts\map.cmd -                  sync, check, deploy; reset nothing
```

It robocopies `PS_MAPSRC` into `media/maps/phuntaxi` **excluding `map.info`**,
runs the checks, calls `scripts\deploy.cmd`, and clears this cell out of a test save
(`PS_TESTSAVE`, falling back to `PI_TESTSAVE`, or the first argument; `-` skips
it). Quit the world to the main menu first: the game writes every loaded chunk
back on the way out, so a reset done mid-game is overwritten.

**The checks are PhunInteriors' and are deliberately not duplicated here.**
`PI_REPO` points at that checkout and defaults to `..\PhunInteriors`.

- **`roomcheck.pl --mod <this repo>`** runs from there and is told about us.
  Our rooms are registered INTO PhunInteriors' registry by our
  `interiors.lua`, so checking our map without their lua reports every
  interior square as claimed by nobody, and checking it without their map
  reports all 990 of their slots as sitting on ground that is not there. One
  run, both maps, one registry. That is why this is not a copy.
- **`fencecheck.pl <our map folder>`** derives the perimeter from the cells
  present rather than from a table, so a one-cell map needs no configuration:
  it works out the four edges and the four corner posts by itself.
- **`tighten.pl`** normalises every `.pzw` in the project folder, ours
  included. Run it **before** exporting (`scripts\tighten.cmd` here runs this
  repo's copy of the same script). The run inside `map.cmd` is after the fact
  and can only repair the project for the next export.
- **`zombies.pl`** on our lotheader, because zero density is the whole point of
  the cell and nothing else checks it. It always exits 0, so `map.cmd` reads
  the line it prints rather than its status.

## map.info

`media/maps/phuntaxi/map.info` is hand written and lives only in this repo. WorldEd
does not export one and a map folder without it is never registered, which
reads in game as the coordinates being wrong. Never mirror the export over the
map folder, and put these two lines back if a re-export ever overwrites it:

```
lots=Muldraugh, KY
fixed2x=true
```

`lots=` is what decides whether the map loads at all. Every `lots=` line is
accumulated into one chain and maps sharing a directory are put in one world,
so a map naming nobody forms its **own** world and its cells never load beside
vanilla or beside PhunInteriors.
