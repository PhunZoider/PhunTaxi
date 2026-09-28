# PhunTaxi

Spawn points for Project Zomboid **Build 42** that you earn, not pick from a
list. Single player and multiplayer.

A new character wakes up in the Taxi Garage, off the map, and takes one free
taxi ride to a place their player knows. You start knowing a few places. The
rest you find by walking the map and picking up pay phones, and what you find
is kept for your next character.

Part of the Phun mod family. Requires PhunInteriors.

## Features

- **Earned spawn points.** Walk near a place to remember it. Pick up a live
  pay phone to remember it. Live phones you have not found ring as you pass.
- **Kept across deaths.** Unlocks belong to the player, not the character, so
  every place you find is somewhere your next character can start.
- **One free ride.** A new character leaves the Taxi Garage by taxi to any
  place their player knows. After that, the map is a map.
- **Taxi between pay phones** (optional). Fast travel between phones you
  know, for a fare in PhunMart change.
- **Build your own pay phones.** Craft a kit at Electricity 4 and put one up
  where you want to come back to.
- **Nobody rides into your safehouse.** Checked before anybody moves.
- **Admin setup that survives a wipe.** Add spawn points and keep pay phones
  from the right click menu or an in game editor; it is all saved to
  `PhunTaxi.json`, outside the save.
- **Every constraint is a sandbox option.**
- **Open to other mods.** Register your own spawn points from one vanilla
  hook.

## Documentation

| Page | For |
|---|---|
| [Playing](Docs/playing.md) | Players: waking up, finding places, pay phones, the taxi, building a phone |
| [Sandbox options](Docs/sandbox-options.md) | Server owners: every option and its default |
| [Running a server](Docs/admin.md) | Admins: world setup, the editor, `PhunTaxi.json`, console commands, wipes |
| [Adding spawn points](Docs/modding.md) | Mod and map authors: the registry API and events |
| [How it works](Docs/how-it-works.md) | Anybody curious why it behaves the way it does |
| [The map](Docs/map.md) | Map work on the Taxi Garage cell |

## Requirements

- Build 42.
- **PhunInteriors** (required). The Taxi Garage is one of its rooms.
- PhunMart (optional), for taxi fares.
- PhunZones (optional), to lock the Taxi Garage cell down further.

PhunTaxi ships a one cell map, cell 87,49. Another map mod using that cell
will conflict.

## Status

**Pre-release.** A new character has been put in the Taxi Garage on a
server. Everything else is written and covered by the automated tests but has
not yet been seen working in game: the picker, the rides, pay phones, the
taxi, building phones, the editor and `PhunTaxi.json`.

The four shipped spawn points have been checked in game, and each has a pay
phone behind its arrival square. See [Running a server](Docs/admin.md#things-to-know).

What is unproven, and what to watch for, is listed in `CLAUDE.md` under
"Known gaps".

## Development

```bash
bash Tests/run.sh
```

Parses every Lua file with LuaJIT, runs six static checks, then the specs in
`Tests/lua/`. The specs load PhunInteriors' `json.lua` from a checkout beside
this one (`../PhunInteriors`), or from wherever `PHUNINTERIORS` points. It
fakes just enough of the game to test the pure Lua; anything that needs a
real map square is tested in game or not at all.

The helper scripts are in `scripts/`:

| Script | What it does |
|---|---|
| `deploy.cmd` | Builds the mod, the `PhunTaxiTest` id variant and Workshop staging for each. Runs on every save in VS Code. |
| `map.cmd` | Syncs a WorldEd export into the repo, runs PhunInteriors' map checks, deploys and resets a test save. See [map.md](Docs/map.md). |
| `tighten.cmd`, `tighten.pl` | Fixes WorldEd's border lot rects. Run between saving in WorldEd and exporting. |
| `shadow.pl` | One of the static checks: a local redeclared inside one function. |

`CLAUDE.md` has the architecture, the house rules and the known gaps.
