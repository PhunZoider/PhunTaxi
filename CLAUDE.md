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
  media/lua/shared/PhunTaxi/   core, tools, points, phones, phone_guards,
                                garage_guard, taxi, interiors, zones, defaults, candidates,
                                map_phones (generated)
  media/lua/server/PhunTaxi/   unlocks, placement, arrival, phone_swap, store,
                                rides, building, server_{commands,events}
  media/lua/client/PhunTaxi/   client_{main,commands,context,events,phone,
                                taxi,admin,viewpoint}
  media/lua/client/PhunTaxi/ui/  picker, editor, map_panel, list_panel (vendored),
                                  ui_utils
  media/lua/shared/Translate/EN/  ContextMenu, IG_UI, Sandbox, ItemName, Recipes (.json)
  media/scripts/                 PhunTaxi_Items.txt (the kit and its recipe),
                                 PhunTaxi_Sounds.txt, PhunTaxi_Models.txt
  media/spriteModels.txt         our phone sprites drawn as PhunTaxi.PayPhone
  media/models_X/PhunTaxi/,
  media/textures/PhunTaxi/      the phone model and texture (generated)
  media/viewpoint/              Project Viewpoint model pack: the taxi
                                (generated by Art/taxi/make_taxi.py)
  media/maps/phuntaxi/          the Taxi Garage cell, 87,49 (see Docs/map.md)

Docs/                      player, admin, modder and map docs; see README.md
Art/phone/make_phone.py    builds the phone model and texture in Blender
                           (blender -b --factory-startup --python ...), into
                           the mod, plus phone.blend and previews; xclude
                           keeps Art/ out of Workshop staging
Art/taxi/make_taxi.py      builds the Viewpoint taxi pack in Blender from
                           vanilla's CarTaxi FBX, wheel and skin, into
                           media/viewpoint/, plus taxi.blend and a preview
scripts/deploy.cmd         the four deploy trees, run on every save
scripts/map.cmd            sync a WorldEd export, check, deploy, reset a save
scripts/tighten.{cmd,pl}   fix WorldEd's border lot rects, before exporting
scripts/shadow.pl          the shadows static check, called by Tests/run.sh
scripts/phones.pl          every pay phone the server's Map= list puts down,
                           read from the lotpacks: CSV, or --lua for
                           map_phones.lua

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
Tests/lua/phones_spec.lua  the swap table, spacing, a swapped phone as a point,
                           the pool: ranks, spacing, dropping, the shipped
                           list and a whole pool resolve, timed
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
- **`Core.tools.sort`, not `table.sort`, for any list that can grow** (pool
  keys, points, store keys). Kahlua's `table.sort` is a recursive quicksort
  and overflowed the stack on the pool's thousand keys on a dedicated server
  (`Stack overflow` in `partition_nocomp`). LuaJIT's does not, so the specs
  cannot catch it.
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

**Every square a phone may go on is known up front, and ranked once per
world.** The pool (`Core.phones.candidates`) is the pay phones the maps put
down (`map_phones.lua`, generated by `scripts/phones.pl --lua` from the
lotpacks of every map in the server's `Map=`, offered by `Core.addMapPhone`
with `replace` set, gated by each map's mod id) and the spots for the voids
(`Core.addPhoneCandidate`, in `defaults.lua` and `candidates.lua`; a spot on
a map phone's square replaces it). `PhoneSwap.resolve` gives each square a
random rank the first time the world sees it (`Core.data.phoneRanks`; the
last two digits are its chance roll), walks them in rank order and takes
each that is `PhoneDistance` (or its zone's) from every phone standing and
every one taken so far, on a bucketed grid. A taken square is a record at
once (`candidate`, `pending`), so it reserves its spacing, and is put up by
`restore` when its square loads: a spot on nothing, a map phone only over the
vanilla phone standing there, facing as that one does. **Only a pending phone
ever moves**, so resolve runs again whenever anything it reads changes (the
pool's version, a phone added or forgotten, a square dropped, the zones
becoming readable) and needs no stored result. A map phone whose square
loads with no vanilla phone, and a pool phone carried off, are retired for
the world (`Core.data.phoneDropped`), and the next in rank nearby takes the
place. Resolve is lazy, on the first square load after boot and never in
`start`, so a third party adding to the pool from `OnInitGlobalModData` is
in the first resolve; and not while PhunZones is installed and not set up.
Rolling each phone as its square loaded, which this replaced, let load order
pick the winner of a group and looked at every square in the world.

**A map phone is named at build time, from the lotheader's rooms.**
`phones.pl` writes a fifth field, the room naming the building the phone is
in or on (its own room if telling, else its building's biggest telling one;
booths, generic buildings and malls get none), and `PhoneSwap.labelFor`
reads it off the candidate through `Core.phones.roomWords`, not off the
record, so a regenerated list renames at the next boot. The words are
English on the server, like "Pay phone" always was.

**LoadGridsquare looks only at squares something names.** An index of every
record and every pool square, by column, rules a square out with two table
lookups, and only a named square has its objects read (`PhoneSwap.visit`).
The client does the same for the ring: the pool is shared code, and the
squares of standing phones the pool does not name (kept, built, a point's)
come in the points payload as `phones` (`PhoneSwap.standingKeys`), plus
every `phoneUp`. So a pay phone on a map not in `map_phones.lua` never goes
live on its own; an admin keeps it, and one of ours put down from the item
off the pool is recorded on its first use, not on load.


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
party point is `deleted` on its entry in `PhunTaxi.json`, and `registerPoint` puts
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

**The whole list goes out on join and when the picker opens; a discovery
sends one entry.** `unlocked` carries `point`, built by the same
`Unlocks.entryFor` as the full payload, and the client puts it in place with
`Core.mergePoint` (the `Core.pointBefore` order, which is why an entry
carries `priority`). Only additions travel this way. A rename, a delete or a
released phone is not pushed, so the refresh when the picker opens is what
carries those, and must stay until something else does.

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

The file is **one flat list** (`version` 2, `entries`): a kept phone (the
default, no `type`), a point (`"type": "point"`), or an override (an `id`
and no square, carrying `label` and/or `deleted` for a point the file does
not define). A phone and a point share one shape: `x, y, z` is always where
the traveller stands, and `facing` puts the phone on the square behind. A
phone entry takes no id, because its point id is built from the phone's
square and every account's unlocks name it. A point's id defaults to
`Store.customId` of its square and its label to its coordinates, and
defaults are left out on write. In memory it is still `Core.saved.{points,
phones, labels, deleted}`: `Store.sanitise` takes the list apart and
`Store.document` puts it back, so nothing outside `store.lua` knows the
file's shape. A rename of a point the file defines is written into its own
entry (so Reset name has nothing to go back to), not kept as an override.
A file in the old four table shape, or with `entries` not a list, is
refused whole and never written over.

**Shipped pay phones sit under the file, as PhunZones' zones do.**
`Core.shipped` (filled by a third party, shared) is a list in the file's own
entry shape, checked by the same `Store.sanitise` in `Store.readShipped` and
merged into `Core.saved.phones` at load unless the file has that square. The
file holds only the difference: a phone kept as shipped is never written, so
a later version's list reaches every server; releasing one writes
`kept: false` (`Core.saved.released`), because a line the file never had
cannot be taken out. A shipped label is the phone's **registered** label
(`Store.shippedLabel`, read by `registerRecord`), not an override, so Reset
name goes back to it. A shipped entry's `mods` is read by `readShipped`
only; the file does not take it.

**PhunTaxi's own pay phones are candidates, not shipped kept phones.** The
list in `defaults.lua` is in the file's entry shape (the traveller's square
and a facing) and is offered to `Core.addPhoneCandidate` on the square
behind, so each world ranks and spaces them with the map phones and a town
gets one of its spots. Shipped as kept phones, every world got every one. A spot's `label`
reaches the phone that wins through a name only entry in `Core.shipped`, so
it is still a registered label and Reset name goes back to it.

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
free choice). With no room to be had, or `UseSpawnRoom` off, the character is
placed at their fallback point, as its tooltip promises.

**On a server, pending is standing in the garage's cell**
(`Core.consts.garage`, `Placement.inGarage`), and nothing is stored. The
vanilla regions collapse to one landing square in the cell
(`OnSpawnRegionsLoaded`, so the selector skips itself) whatever
`UseSpawnRoom` says, the garage has no way out but the taxi, and the taxi is
the ride: so a character in the cell is new or rejoined still choosing, one
anywhere else has had their ride, and dying lands the next one there again.
This replaced a `spawnedKey` stamp in player modData, which a server side
write does not persist on a server (seen in game, 2026-09-30). Single
player's selector is never collapsed, so SP keeps the age check and the
stamp, where modData is saved as written. The landing square is REQUIRED
and must be outside every slot: PhunInteriors puts anybody standing in a
slot with no lease back outside. The room is `singleUse`, so PhunInteriors, which knows who
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
   whether the server has the player's real position at `playerSetup`: the
   free ride is standing in the garage's cell, read there. A server side
   write to player modData does NOT persist on a server (seen 2026-09-30), so
   nothing on a server may depend on one; `spawnedKey` is single player only.
2. **The shipped points' phones have never been put up.** The four points in
   `defaults.lua` and the squares behind them were checked in game by hand,
   but each `phone` is put up by `PhoneSwap.restore` on an empty square when
   the square first loads, which is gap 10's unproven `replace` with no old
   object. A point moved in code or in `PhunTaxi.json` needs both squares
   checked again: nothing here can tell a wall from a floor. Every entry in
   `candidates.lua` carries the same risk and the same check, and the list
   ships empty until someone has stood on the squares. The 102 shipped phone
   spots in `defaults.lua` (candidates, drawn per world) were kept in game. The
   first 59 were kept in the old store shape (the phone's
   own square) and converted to the traveller's square by `Core.phoneFront`;
   three of them had a key that disagreed with their own `x, y`
   (2263,14368, 2510,14060, 8140,11432), and the coordinates were taken over
   the key. The Machine Shop (phone at 10646,11061) and Motel (10623,10856) spots
   are offered only with `Muldraugh-Checkpoint` active. The other 43 came from a
   `PhunTaxi.json` already in the traveller's square shape; two in Crossroads
   need `Crossroads-Checkpoint` and four in Maplewood need `Maplewood`. A world
   that ran before they were candidates has the first 59 standing as ordinary swapped phones, and every
   spot is passed over for the phone already on it: only a new save shows the
   ranking, because a wipe of global ModData alone records the standing phones
   again as their squares load.
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
   - The build cursor (`client/.../client_build.lua`), an `ISBuildingObject`
     with `skipBuildAction` whose `tryBuild` drops the drag and calls
     `Client.queueBuildPhone`, so the server's checks are unchanged. Its
     ghost is drawn from the shared sprite (`getSprite(name)`), not a fresh
     `IsoSprite` as vanilla's render does, so `RenderGhostTile` finds the
     sprite model. Unproven: that, R, and the cursor under Viewpoint.
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
   pins drawn in `render` (not `prerender`) landing above the map, the
   list column headers, and the map loading over frames after the window
   (`MapPanel:loadWhenDrawn` runs vanilla's loader calls a few per frame,
   about 12 ms' worth, with "Loading map..." and a bar in its place, and
   shows the map once `isDataLoaded`), for the picker and the editor. Each
   map's `streets.xml` is parsed on the main thread (read off the B42 jar),
   so one big one is still a hitch; with `-debug` the log names any step
   over 50 ms and the total. Closing either window hides it, so its map
   stays loaded for the next open.
   The spawn button works only in the garage on a
   server (`server/.../placement.lua`), and rests on gap 1's position.
   `point.room` is ignored, the spawn square is not checked for being free,
   and there is no joypad support. A player opens it only as the taxi ("Take
   taxi ride" on a `phuninteriors_02_0` to `_39` tile, in the spawn room);
   an admin with the setup menu on gets "Spawn points" anywhere. So a new character
   who closes it must walk back to the taxi, and nothing checks that the
   spawn room has one.
6. **The test id has no `icon.png`.** The mod has both of the images
   `mod.info` names; `Tests/root/PhunTaxi/common/` has only `poster.png`.
7. **Published.** `workshop.txt` is 3812506730 and `Tests/workshop.txt`
   is 3809819336. Both pages go out with whatever the docs say, so an
   unproven feature is not advertised there as working.
8. **The pool has never run in game.** The swap it replaced (a roll on each
   vanilla phone as its square loaded) was seen working on 2026-09-30 at
   Raven Creek, at PhoneChance 100 and PhoneDistance 1: every phone swapped,
   booths and stairwell banks included, and they line up. The swap itself
   (`PhoneSwap.replace`, `restore`) is unchanged. Unproven, in order of
   risk: `resolve` under Kahlua (1 ms for the whole shipped pool under
   LuaJIT, so expect tens of ms, on a square load, whenever something
   changes); that `getActivatedMods():contains` matches the mod ids
   `map_phones.lua` is gated on; a map phone dropping and the next in rank
   going up; and the ring, which is client side
   (`client/.../client_phone.lua`): squares the pool or the payload's
   `phones` names, noted on the client's LoadGridsquare, plus every phone the server
   puts up (`PhoneSwap.replace` broadcasts `phoneUp`, because a phone put up
   on an empty square arrives after the client's load), known phones read from the
   points payload by `Core.phonePointId`, played through a free emitter with
   `PhunTaxi_PhoneRinging` for `PhoneRingSeconds`. Each player's volume
   for it and for `PhunTaxi_DriveOff` is a `PZAPI.ModOptions` slider
   (`Client.volume`, in `client_main.lua`, as PhunSprinters does it),
   applied with `setVolume` on the handle: unproven that it scales the
   clip's own `volume = 0.3f` rather than replacing it, and that
   `player:getEmitter():setVolume` takes the handle `player:playSound`
   returns. The guards
   (`shared/.../phone_guards.lua`) cover pickup, rotate, dismantle,
   sledgehammer and cars (HitByCar is unset on our sprites); admin mode is
   the movables or build cheat, so **turn it off to test them**. Unproven that
   B42's server runs `isValid` on these actions as it completes them, which
   is why they are shared. A phone that still goes missing is forgotten the
   next time its square loads, and a pool square retired. One of ours
   standing with no record (put down
   from the item, or its record lost to a `global_mod_data.bin` wipe such as
   `scripts/map.cmd`'s reset) is recorded when its square loads, if the
   pool names the square, or when somebody uses it
   (`PhoneSwap.recordStanding`): unspaced, unkept, a spawn point like a
   built phone. "Pick up phone" is hidden once the point is in
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
   is removed rather than stored. A point the file itself defines is
   renamed in its own entry instead, so Reset name is never offered for it. Remove, Delete and Restore share one
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
   any phone inside it. The same file adds two int fields to
   `PhunZones.fields` (`phoneChance`, `phoneDistance`, names in
   `Core.consts`), which `PhoneSwap.chanceAt` / `spacingAt` read through
   `getLocation` in place of the sandbox values; unset falls back. Nothing
   calls `getLocation` before PhunZones has set itself up (`PhunZones.inied`):
   the call sets it up, and doing that at our boot threw in its client
   `OnDataBuilt` listener in single player (no player yet) and left it half
   set up. Until then a vanilla phone is left unstamped, and every record is
   located once on the first square load after. Unproven:
   that they show in the editor's Mods group, and that clearing one there
   takes it back to unset (the editor's `saveProp` drops a non number).
12. **The arrival room has run once, on a server.** A new character was put
   in the garage by `PhunInteriors.enterRoom`. The picker no longer opens by
   itself: a pending character gets a pulsing line over the taxi instead
   (`client/.../client_taxi.lua`, drawn with `isoToScreenX/Y` on
   `OnPreUIDraw`), and opens the picker from the taxi's context menu.
   `Arrival.landing` is the middle of cell 87,49, unchecked for open floor, so
   the vanilla regions collapse to it, whatever `UseSpawnRoom` says, and the
   selector should skip itself. A new character who is not put there is never
   offered the ride on a server. Unproven, in order of risk:
   that the collapsed table reaches clients (`GameServer` calls
   `getSpawnRegions` and clients read `getServerSpawnRegions()`, and it fires
   `OnSpawnRegionsLoaded` only where `not isClient()`); that the landing
   square is floor; the hint's height over the taxi (`LIFT`). Single player's
   selector runs in the main menu before any server file loads, so it is never
   collapsed there.
13. **The 3D phone has never been drawn in game.** `media/spriteModels.txt`
   puts `PhunTaxi.PayPhone` on `phuninteriors_01_16` to `_19`. The game's
   `SpriteModelManager` reads that file from every active mod and attaches
   each entry by sprite name, so describing PhunInteriors' tileset from here
   is expected to work. No installed mod ships its own `modelScript` this way;
   they all use vanilla's. Unproven, in order of risk: that a mod's model
   script and `.glb` resolve at all; the rotations, first reasoned from the
   Sprite Model Editor's axes (x east, z south, y up) as S 0, E 90, W -90,
   N 180. In game every facing came out backwards (2026-10-07, S and N
   first, then E and W, in both views since Viewpoint captures vanilla's
   own model draw), so all four are 180 from that: E -90, S 180, W 90, N 0.
   The build cursor's ghost is drawn with the model, so it shows all four;
   the scale, taken from vanilla's own
   IsoObject sources (tile 1, storey 2.449, `undoCoreScale`). Tune them in
   the debug menu's Sprite Model Editor, which saves back into the file. The
   object's collision and properties still come from the tile, so the code
   is untouched. A phone of ours with the mod off draws as the old sprite.
14. **The Viewpoint taxi is drawn, and its menu works, in game**
   (2026-10-07). Project Viewpoint
   (3809306528) drew nothing for `phuninteriors_02_*`, so in 3D the garage
   had no taxi. `media/viewpoint/` is a model pack, registered by
   `client_viewpoint.lua` as PhunInteriors registers its own, that binds
   vanilla's CarTaxi (body, four `Vehicles_Wheel`s, `vehicle_cartaxishell`
   with the wheel packed beside it) to `phuninteriors_02_14` only, half a
   tile east, which centres it on the 2x5 footprint. That is the one facing
   the map places (`02_10` to `_19`, front north, read off the lotpack); the
   other thirty tiles are unbound, so a taxi placed another way is still
   invisible in 3D. `make_taxi.py` parses the ASCII FBX itself (Blender
   refuses ASCII) and is regenerated, never hand edited. Viewpoint's
   crosshair picks it and "Take taxi ride" is offered on its [F] menu: the
   option passes the taxi tile as a trailing argument, PhunInteriors' rule
   for that menu, which keeps an option only when an argument IS the object
   under the crosshair. Still unproven: "Install pay phone" passes the
   clicked object the same way, and whether the floor counts as one.
   The red ceiling and green walls seen round it on 2026-10-07 were
   PhunInteriors' pack built with `--debug`, not this one.
   The taxi hint (gap 12) is screen space, so in 3D it hung at a fixed spot
   and followed the player. While the `Viewpoint` global exists (its Java is
   loaded; it exposes no "is 3D on") the line is not drawn and the same text
   goes up as a halo note instead, on first sighting and every 60 scans after
   while the taxi is in range. Unproven that Viewpoint draws halo notes.
   Viewpoint keeps the mouse for looking unless `UIManager.isModalVisible()`,
   so the picker and the editor each carry `tools.freeCursorWhileShown`
   (`ui/ui_utils.lua`, PhunMart2's fix): a zero-size child with capture on
   that passes every event through. Middle mouse is Viewpoint's own cursor
   toggle, the stopgap if it fails.
   A phone's options showed only on its post or lower half, in both views.
   The iso picker tests the 2D sprite's mask and scores what it hits, and
   over a phone against a wall it can return the wall, on the square behind;
   Viewpoint's crosshair picks a wall within 0.08 of a tile edge first. So
   `findPhone` also looks at the squares in front (+x, +y, both) of each
   clicked one, and every phone option carries the clicked object last for
   Viewpoint's menu. PhunMart's vending machines show the same thing.
15. **The garage door guard has never run.** The roller door is vanilla's
   `walls_garage_02_51` to `_53`, real garage door tiles (`doorN`,
   `GarageDoor`), so it is an IsoDoor in game (see `Docs/map.md` for how
   `spawn.tbx` lays it). `shared/.../garage_guard.lua` makes
   `ISOpenCloseDoor:isValid` refuse a shut IsoDoor in the garage's cell
   with a room on one side only (`getRoom` on `getSquare` and
   `getOppositeSquare`), outside admin mode (the phones' cheat check). That
   is the roller door and the office's back door; the doors between rooms
   still work. A lock would not hold: anyone inside may unlock by hand.
   Unproven: that every way of opening it, the interact key in particular,
   goes through `ISOpenCloseDoor`, that the server asks `isValid`, and that
   the room test holds on a client. Breaking a door with a weapon is not
   stopped. The south and east walls carry the rooms' interior sets as
   their exterior (`Docs/map.md`), unproven in 3D and in the iso view.
