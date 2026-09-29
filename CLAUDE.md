# PhunTaxi

Project Zomboid **B42** mod. Spawn points that are earned rather than listed:
a character starts knowing a few and finds the rest by walking the map, and a
new character wakes up in an off grid room rather than on a kerb. SP and MP
share one code path.

Author: UburGeek. Part of the Phun mod family (PhunLib, PhunCure, PhunLewt,
PhunZones, PhunInteriors, PhunMart2, PhunRooms, PhunServer2...). GitHub org:
`PhunZoider`.

## Status

**Scaffolding. Nothing has run in game.** `Tests/run.sh` is green, which is
real verification of the registry and the unlock logic and no verification at
all that PZ agrees. What exists is the registry, the unlock bookkeeping, the
dispatch layer, the context menu, the picker (see Known gaps 5) and the
translations. What is unproven or missing is listed under "Known gaps" below,
and each one is marked `TODO` at the place it belongs.

The player, admin and modder docs are in `Docs/` (`playing`, `admin`,
`sandbox-options`, `modding`, `how-it-works`), linked from README.md, and
`workshop.txt` is the Workshop page. A change a player or an admin would
notice (an option, a menu entry, a message, what survives a wipe) is not done
until those say so too.

The sibling mod to read before changing anything here is **PhunInteriors**.
Its `CLAUDE.md` carries the B42 API table this family has paid for, and none
of it should be re-derived.

## Verify before you claim anything works

```bash
bash Tests/run.sh
```

Parses every lua file with LuaJIT, then runs six static checks and the specs
in `Tests/lua/`. Each static check catches a bug class LuaJIT cannot see:

- **namespace**: no function shadowing a field declared on the `PhunTaxi`
  table in `core.lua`. A `function Core.points()` helper would *replace* the
  registry table at file load time, silently, and the first registration would
  index a function. That has happened in this family.
- **unlocks**: no writer of `Core.unlocked` other than `unlocks.lua`. It is a
  cache of the account record, and a copy maintained in two places
  disagrees with the truth.
- **shadows**: no local redeclared at the top level of one function
  (`scripts/shadow.pl`). LuaJIT parses one happily and the damage shows up
  somewhere else entirely.
- **dashes**: no em dashes. See House style.
- **globals**: nothing declared global at the top of a file but `PhunTaxi`.
  A `function name()` without `local` is the easy slip.
- **json**: every translation file parses. One stray comma loses the whole
  file, and every key in it shows raw.

LuaJIT cannot catch API misuse. PZ globals do not exist outside the game, and
LuaJIT accepts `next()` and `loadstring`, neither of which B42 exposes.

`Tests/lua/stubs.lua` fakes the handful of globals the files touch while
loading. It is **not** a mock of the game: anything needing an `IsoGridSquare`
is tested in game or not at all. Add to it when you change registry or unlock
logic; do not try to grow it into a simulator.

Deployment is VS Code `emeraldwalk.runonsave` (see `.vscode/settings.json`),
which runs `scripts/deploy.cmd` on every save and builds four trees: the
playable mod, the test id variant `PhunTaxiTest`, and Workshop staging for
each. `xclude` is the xcopy exclude list. Every `.cmd` and `.pl` lives in
`scripts/`, as in PhunInteriors, and each `.cmd` finds the repo root as its
own parent folder. `scripts` cannot go in `xclude`: xcopy matches entries as
substrings, and it would take `media/scripts/` with it, so `deploy.cmd`
removes the staging copy's `scripts/` the way it removes `Tests/`.

## Layout

Standard Phun conventions, mirroring PhunInteriors and PhunCure2. Everything
ships under `common/`. There is no root `mod.info` and no versioned (`42.x/`)
folder.

```
Contents/mods/PhunTaxi/common/
  mod.info                  id=phuntaxi, versionMin=42.0.0, require=phuninteriors
  media/sandbox-options.txt
  media/lua/shared/PhunTaxi/   core, tools, points, phones, phone_guards, taxi,
                                interiors, zones, defaults
  media/lua/server/PhunTaxi/   unlocks, placement, arrival, phone_swap, store,
                                rides, building, server_{commands,events}
  media/lua/client/PhunTaxi/   client_{main,commands,context,events,phone,
                                taxi,admin}
  media/lua/client/PhunTaxi/ui/  picker, editor, map_panel, list_panel (vendored),
                                  ui_utils
  media/lua/shared/Translate/EN/  ContextMenu, IG_UI, Sandbox, ItemName, Recipes (.json)
  media/scripts/                 PhunTaxi_Items.txt (the kit and its recipe),
                                 PhunTaxi_Sounds.txt
  media/maps/phuntaxi/          the Taxi Garage cell, 87,49 (see Docs/map.md)

Docs/                      player, admin, modder and map docs; see README.md
scripts/deploy.cmd         the four deploy trees, run on every save
scripts/map.cmd            sync a WorldEd export, check, deploy, reset a save
scripts/tighten.{cmd,pl}   fix WorldEd's border lot rects, before exporting
scripts/shadow.pl          the shadows static check, called by Tests/run.sh

Tests/run.sh               syntax check, static checks and specs
Tests/lua/stubs.lua        PZ globals, faked just enough to load
Tests/lua/points_spec.lua  the registry, the sort, discovery and the payload
Tests/lua/store_spec.lua   PhunTaxi.json: the wipe round trip, bad files,
                           kept phones. Loads PhunInteriors' json.lua from
                           ../PhunInteriors (or $PHUNINTERIORS).
Tests/lua/taxi_spec.lua    near discovery, fares, rides and every refusal,
                           safehouses, building and taking down phones
Tests/lua/arrival_spec.lua who is put in the arrival room, the fallback when
                           there is no room, and the regions collapsing
Tests/lua/zones_spec.lua   the Taxi Garage zone: its flags, and its rect
                           against the cell and objects.lua
Tests/lua/phones_spec.lua  the swap table, spacing, a swapped phone as a point
Tests/lua/picker_spec.lua  region grouping and the once only spawn button
Tests/lua/editor_spec.lua  renames surviving a reboot, and an admin port that
                           grants nothing
Tests/workshop.txt         the Workshop page for the test id
Tests/root/PhunTaxi/      overlay carrying the test id. The path must mirror
                           the live mod folder or the overlay silently does
                           nothing.
```

House style, taken from PhunInteriors and PhunCure2:

- `core.lua` holds `name`, `consts`, `commands`, `events`, `settings`,
  `modules`.
- `*_commands.lua` **returns** a `Commands` table; `*_events.lua` dispatches
  into it.
- Server files open with `if isClient() then return end`, client files with
  `if isServer() then return end`. In SP both are false, so both load.
- Everything hangs off the `PhunTaxi` global. **No other globals.**
- **And nothing may be hung off `PhunTaxi` under a name `core.lua` already
  declares.** `Tests/run.sh` refuses it.
- Settings cached via `Core.getOption` and refreshed on `EveryTenMinutes`.
- **No em dashes. Anywhere.** Not in this file, not in code comments, not in
  commit messages, not in anything written for a player to read, and not in a
  reply. Where one would go, use `--`, or recast around a comma, a colon or a
  full stop. `Tests/run.sh` checks.

## Architecture, and why

**One code path for SP and MP.** `Core.dispatch` / `Core.respond` check
`Core.isLocal` and either round-trip through `sendClientCommand` or call the
handler directly. Never write a separate SP implementation: two halves drift.

**Unlocks are per PLAYER, and the account record is the truth.** They live
in global ModData under `Core.data.accounts[Core.accountKey(player)]`, as
`{unlocked, lastChoice}`. The key is the username on a server and the local
player slot in SP (vanilla's fishing does the same, because an SP username is
not a key). `Core.unlocked` is the server side cache, rebuilt on login.

They were per character once, in player modData, and that was reversed on
purpose: the only moment an unlock is worth anything is choosing where to
wake up, and that moment belongs to the NEXT character, because dying makes a
new character with fresh modData. A per character list died with the one who
earned it. The price is that `global_mod_data.bin` now carries everyone's
exploring. A character still holding a legacy list in its modData has it
folded into the account on first read and cleared, so there is one list and
not two that disagree.

**The game is a taxi fed by phones.** A new character gets one free ride out
of the spawn room (the spawn command, once, `placement.lua`), to anything
the account knows. Phones are what a player finds to widen that, so the
default is that a phone counts only when used; `PhoneDiscoverRadius` above 0 makes
walking up enough and rings once as the cue. `TaxiFastTravel` (off by
default) is paid travel between known phones only, fare from PhunMart's
"change" pool (`server/rides.lua`), charged **after** `sendTo` accepts, so a
refused move costs nothing. The fare sum is shared (`shared/taxi.lua`) so the
quote on the Go button and the charge cannot disagree.

**No ride ever lands in somebody else's safehouse**, and that is checked
**before** the move, not by bouncing back after: `Rides.safehouseBlocks`
asks `SafeHouse.getSafehouseOverlapping`, which walks the claim list and so
answers for an unloaded destination (see PhunInteriors' API table, including
the half open rectangle). This one check is what makes player built phones
safe, which is why building allows indoors and one's own safehouse: nobody
but members can ride there.

**A built phone is a phone record with `owner` and `built`**, built by a
request the server checks in full before anything is placed
(`server/building.lua`), from a kit that is not a moveable. Spaced against
every phone, limited per account, never in the store file, so a wipe takes
it. Its owner key is also stamped on the object, but only for the client's
"Take down" menu; the record decides.

**A point can ask for a phone, and keeps its own id.** `registerPoint`'s
`phone` (a facing) puts one of ours on the square behind the point, so a
start point is a taxi stop. The server makes it a phone record owned by the
point (`record.point`), treated as kept (never forgotten, put back when its
square loads without it) and with no point of its own: using it grants the
owner, a ride goes to and from the owner. `PhoneSwap.syncDeclared` follows
`Core.registryVersion`, so a point registered late takes its phone over, and
one deleted leaves it as an ordinary swapped phone. Because an owned phone's
point id is not built from its square, **the client knows a phone by its
square key** (`Core.phoneKey`), which the payload carries as `phone` on a
known point, and a ride's destination is any point with a `phoneKey`, not a
`used` one.

**A starter is granted on read, not stamped once.** So a point added to the
start set in a later version reaches existing characters and there is no
migration to write.

**Discovery defaults to `explore`, never to `start`.** The safe default is the
one that gives nothing away, so a point meant to be known has to say so. Same
shape as PhunInteriors' rule that a position must have no default: a wrong
default fails *plausibly* rather than loudly.

**Where a point is, is data, not arithmetic.** `locations`-style arithmetic
was refused here before it could be written, for the reason PhunInteriors
removed its own: a set laid out on a grid is three lines shorter and puts half
the points in the river. A genuinely regular set is a `for` loop in the caller.

**A removed point is filtered on read, not deleted from everybody.** So
`removePoint` does not walk every character's list, and taking a point set out
temporarily and putting it back costs nobody their exploring.

**An admin deletes a point with a tombstone, as PhunZones does.** Code
registers its points again on every boot, so deleting a shipped or third
party point is an id in `PhunTaxi.json`'s `deleted`, and `registerPoint` puts
a tombstoned id in `Core.deleted` instead of `Core.points`. Every reader looks
in `Core.points` and needs no filter of its own; the graveyard exists for the
editor to list and for Restore to put back. A point an admin added on a
square is removed from the file instead (`Store.takeOut`), because a
tombstone left behind would catch the next point added there. Phones are
released or taken down, never tombstoned, and the last start point is
refused.

**Reverse indexes rebuild lazily**, on the first read after any registration.
That is what lets a third party register from any vanilla hook, including one
that fires long after our boot sequence. The consequence is that **nothing may
warn about a missing link at boot**: at boot it cannot tell "not registered
yet" from "the mod that owns it is not installed". Say it at the point of
refusal instead.

**Discovery is swept on a timer, not on every movement update.** A point is a
place you walk to and stay near for a moment, not a tripwire you can sprint
through, and running a sweep over every online player at 60Hz to notice
something that changes once a session is how a mod becomes the reason a server
is slow.

**The payload honours `ShowUndiscovered` server side.** A client handed the
coordinates can draw them whatever the option says, so an option enforced only
in the UI is not enforced at all.

**PhunInteriors is a hard dependency** (`require=phuninteriors`, and
`phuninteriorstest` for the test id). This mod uses its off grid room, its
map instancing, its tiles and textures (see `Docs/map.md`) and its way of
moving a player, so there is no working mode without it. Older code and
comments that guard for it being absent are from when it was a soft hook.

**What an admin sets up lives in `PhunTaxi.json`, not in ModData.** Points
added from the context menu, pay phones kept, and every rename. It is in the
game's Lua folder, which a wipe does not touch, so the next world starts with
them; ModData is in the save and goes with it. `server/store.lua` owns it,
with PhunInteriors' rules for the two file calls (`false` to `getFileReader`,
encode before `getFileWriter`) and PhunInteriors' `json.lua`, required rather
than copied because PhunInteriors is a hard dependency. It is read **before**
registration (a rename is read at registration) and its points register
**after** the code's, so a point of the same id replaces a shipped one. Every
change is written at once and undone if the write fails; a file that did not
parse is never written over. A kept phone is never forgotten: a square that
loads without it gets one of ours put back, over a vanilla phone if one is
there, which is what carries it into a new world. It is still keyed by its
square, so its point id is the one the client rings by.

**Moving a player is `PhunInteriors.sendTo`, never a teleport of our own.**
A bare teleport out of a room leaves PhunInteriors believing the player is
still in it: occupancy, lease, leash and the client's "Step outside" all stay
behind. `sendTo` is PhunInteriors' own exit with the destination replaced,
and it pushes zombies off the landing square once the player's client
reports the arrival. It lives in PhunInteriors' `server/transit.lua` and is
covered by that repo's `sendto_spec.lua`.

The room registers with **no binding**. A PhunInteriors binding says which
vehicles or objects may *lease* a room, and nothing leases this one: a spawn
room is entered by being a new character, which is a different question from
the entitlement machinery and must not be squeezed into it.

**A new character is put in the room by the server, not by the vanilla
selector** (`server/arrival.lua`). On `playerSetup`, a pending character is
handed to `PhunInteriors.enterRoom` with `share = true` (a server may have one
spawn room, and two new characters in it beats one refused) and `exit = false`
(the taxi is the only way out, so there is no "Step outside" to walk off with a
free choice). Where vanilla put them only matters for a moment, which is why
collapsing the vanilla regions to one landing square (`OnSpawnRegionsLoaded`,
so the selector skips itself) is tidiness and not the mechanism. The landing
square must be outside every slot: PhunInteriors puts anybody standing in a
slot with no lease back outside. With no room to be had, the character is
placed at their fallback point and their choice is used, as `UseSpawnRoom`'s
tooltip promises. The room is `singleUse`, so PhunInteriors, which knows who
is last out, hands it back.

**Register from `Events.OnInitGlobalModData`, never from one of PhunInteriors'
own events.** `Events` is a plain Kahlua table with no metatable, so a key
exists only once `LuaEventManager.AddEvent` has been called for it. If our
file loads first, `Events[theirs]` is nil and the `.Add` throws, and firing
later cannot rescue a listener that was never attached. `OnInitGlobalModData`
always exists and fires everywhere, including on a dedicated server;
`OnGameStart` is triggered only from `zombie.gameStates.IngameState`, which a
dedicated server does not have.

## Known gaps

1. **Nothing has run in game.** The whole mod. The first thing to watch is
   whether a server side write to player modData persists on a **dedicated**
   server: it is settled from the jar for PhunInteriors' entrance key and
   nothing has confirmed it for ours. Unlocks no longer depend on it (they are
   in global ModData), but `spawnedKey` does: if the client's copy wins, a
   character who rejoins is offered a second free choice.
2. **The shipped points' phones have never been put up.** The four points in
   `defaults.lua` and the squares behind them were checked in game by hand,
   but each `phone` is put up by `PhoneSwap.restore` on an empty square when
   the square first loads, which is gap 10's unproven `replace` with no old
   object. A point moved in code or in `PhunTaxi.json` needs both squares
   checked again: nothing here can tell a wall from a floor.
3. **The arrival room's 64 slots have never been filled in game.**
   `interiors.lua` lists them, 8x8 across cell 87,49, a 15x10 box over a
   14x9 floor, each read out of the lotheader with PhunInteriors'
   `scripts/rooms.pl` rather than off a grid, and checked with its
   `scripts/roomcheck.pl` (`scripts/map.cmd` runs it). A slot is still
   shared when full (gap 12). The generator is on the office roof
   (12,1 at z=1).
4. **The taxi and player built phones have never run in game.**
   `taxi_spec.lua` covers the order and outcome of every check without a
   square. Unproven, in order of risk:
   - The recipe (`scripts/PhunTaxi_Items.txt`): that it parses, the item ids
     (`Base.ElectricWire`, `Base.SheetMetal`, `Base.ElectronicsScrap`,
     `Base.Screws`) and the `base:screwdriver` tag exist in B42, and it shows
     under Electrical at Electricity 4. The icon is borrowed
     (`ElectronicsScrap`); there is no taxi phone icon anywhere yet.
   - `PhoneSwap.replace` on an empty square (gap 10), now also how a built
     phone goes up, and whether the owner stamp in modData reaches the client
     with `transmitCompleteItemToClients`. If it does not, "Take down" is
     never offered.
   - The build checks read `getFloor`, `isSolid` and `isSolidTrans`, and the
     take down gives the kit back with `AddItem` plus
     `sendAddItemToContainer`. Only the kit spend is PhunInteriors' proven
     pattern.
   - `getCell():getZombieList()` on a dedicated server for the zombie check.
   - PhunMart's wallet: `getBalance` / `adjustByPool` with the "change" pool
     and the `getWallet` resync after, copied from its own server commands.
   - `ISButton:setWidthToTitle` as Go gains and loses its fare, and a picker
     switching between spawn and taxi mode.
   Object modData still does **not** survive a pickup reliably, which is why
   nothing about a built phone lives on the object but the menu's hint.
5. **The picker is written and has never been opened.** `client/.../ui/`:
   `picker.lua` is the window and an accordion list (click a city to open it
   and fit the map to it), `map_panel.lua` is a bare `UIWorldMap` set up call
   for call from `ISWorldMap:initDataAndStyle`, and `list_panel.lua` is
   PhunMart2's panel vendored via PhunInteriors' copy. `form_panel.lua` was
   **not** vendored because nothing here is a form; if one is ever added, the
   trap is that `FormPanel` calls `self._onApply(self)` and passes the
   **form**, not a values table. Unproven in game, in order of risk:
   `uiToWorldX(x, y, zoom, cx, cy)` as the zoom-to-fit probe, `transitionTo`,
   pins drawn in `render` (not `prerender`) landing above the map, and the
   list column headers. The spawn button is once only per character
   (`server/.../placement.lua`, stamped in modData under `spawnedKey`), and
   rests on the same unproven dedicated server modData write as gap 1.
   `point.room` is ignored, the spawn square is not checked for being free,
   and there is no joypad support. A player opens it only as the taxi ("Take
   taxi ride" on a `phuninteriors_02_0` to `_39` tile, in the spawn room);
   an admin with the setup menu on gets "Spawn points" anywhere. So a new character
   who closes it must walk back to the taxi, and nothing checks that the
   spawn room has one.
6. **`icon.png` and `poster.png` are missing.** `mod.info` names both, and
   `Tests/root/PhunTaxi/common/` needs its own pair for the test id.
7. **`workshop.txt` has an empty `id=`.** Fill on first publish.
8. **The pay phone swap has never run in game.** PhunMart's vending machine
   swap applied to phones (`shared/.../phones.lua` for the table,
   `server/.../phone_swap.lua` for the roll, the swap and the records).
   Unproven, in order of risk: that `LoadGridsquare` modifying a square
   behaves as it does for PhunMart; that "Facing = E" means the player
   stands east of the phone, which is where a phone's spawn point is put;
   and the ring, which is entirely client side (`client/.../client_phone.lua`):
   squares noted on the client's LoadGridsquare, known phones read from the
   points payload by `Core.phonePointId`, played through a free emitter with
   `PhunTaxi_PhoneRinging`. The guards
   (`shared/.../phone_guards.lua`) cover pickup, rotate, dismantle,
   sledgehammer and cars (HitByCar is unset on our sprites); admin mode is
   the movables or build cheat, so **turn it off to test them**. Unproven that
   B42's server runs `isValid` on these actions as it completes them, which
   is why they are shared. A phone that still goes missing is forgotten the
   next time its square loads. One of ours standing with no record (put down
   from the item, or its record lost to a `global_mod_data.bin` wipe such as
   `scripts/map.cmd`'s reset) is recorded when its square loads or when
   somebody uses it (`PhoneSwap.recordStanding`): unspaced, unkept, a spawn
   point like a built phone. "Pick up phone" is hidden once the point is in
   the player's payload as known. The walk goes to the square in front,
   falling back to `luautils.walkAdj`.
9. **The admin editor has never been opened.** `client/.../ui/editor.lua`,
   opened from the admin panel and the debug menu (`client_admin.lua`, as in
   PhunInteriors), so in single player only in debug mode. Every registered
   point in a flat list with filter tabs by kind and a live distance column,
   sorted nearest first, the whole map beside it, and Go there, Rename and
   Reset name. Go there is `sendTo` without releasing any room, and grants nothing, sets no
   last choice and stamps no placement. A rename is an override in
   `PhunTaxi.json` (`Core.saved.labels`), read by `registerPoint`, so it
   survives the next boot and a wipe; set back to the registered label it
   is removed rather than stored. Remove, Delete and Restore share one
   button, titled by row; deleted points are listed in a Deleted tab only
   and get no map pin. Players see a rename the next time their
   picker asks for its list. Unproven: the `ISTextBox` callback shape
   (copied from PhunInteriors' `binding_form.lua`) and every map risk in
   gap 5.
10. **`PhunTaxi.json` has never been written by the game.** The store,
   the admin setup submenu on the context menu (only once the admin turns
   it on with the editor's "Setup menu" button, a client flag that starts
   off each session, and a new phone faces the admin, from where they
   stand), and Keep, Release, Found by
   and Remove in the editor. Unproven, in order of risk: that a kept phone
   put on a square with nothing on it (`PhoneSwap.replace` with no old
   object) behaves as the swap does, and blocks movement;
   `getFileReader`/`getFileWriter` landing in `Zomboid/Lua/` on a dedicated
   server as they do for PhunInteriors; the `ISContextMenu:getNew` /
   `addSubMenu` submenu; and `ISButton:setTitle` flipping Keep and Release.
   Nothing checks that an added point's square is free, so it carries gap
   2's risk: the admin clicked it, which is better evidence than a
   placeholder has, and is still not proof.
11. **The Taxi Garage zone has never been read by PhunZones in game.**
   `shared/.../zones.lua` adds it, at load and only when `phunzones2` or
   `phunzones2test` is active, to the table `require "PhunZones/data"`
   returns: the whole of cell 87,49, zeds removed, and no safehouse,
   building, placing, pickup, scrap or sledgehammer. A soft hook: without
   PhunZones the cell is still zombie free by its lotheader. Unproven: that
   B42's `require` hands us the same table PhunZones' `core.lua` and
   `process.lua` hold, which the whole hook rests on. An admin setting up the
   garage is blocked like anyone else unless PhunZones' "Staff ignore zone
   restrictions" is on. PhunZones also names the garage as the region of
   any phone inside it.
12. **The arrival room has run once, on a server.** A new character was put
   in the garage by `PhunInteriors.enterRoom`. The picker no longer opens by
   itself: a pending character gets a pulsing line over the taxi instead
   (`client/.../client_taxi.lua`, drawn with `isoToScreenX/Y` on
   `OnPreUIDraw`), and opens the picker from the taxi's context menu.
   `Arrival.landing` is the middle of cell 87,49, unchecked for open floor, so
   the vanilla regions collapse to it and the selector should skip itself; the
   collapse reads the sandbox option directly because the server may build its
   regions before the settings cache is filled. Unproven, in order of risk:
   that the collapsed table reaches clients (`GameServer` calls
   `getSpawnRegions` and clients read `getServerSpawnRegions()`, and it fires
   `OnSpawnRegionsLoaded` only where `not isClient()`); that the landing
   square is floor; the hint's height over the taxi (`LIFT`). Single player's
   selector runs in the main menu before any server file loads, so it is never
   collapsed there.
