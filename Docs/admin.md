# Running a server

This page is for server owners and admins. For what each sandbox option does,
see [Sandbox options](sandbox-options.md).

## Requirements

| Mod | | What for |
|---|---|---|
| PhunInteriors | **required** | The Taxi Garage is one of its rooms, the map uses its tiles, and every ride moves the player through it. |
| PhunMart | optional | Taxi fares, paid in its change. Not needed for the free first ride, or for a taxi with both fare options at 0. |
| PhunZones | optional | Adds a **Taxi Garage** zone over the garage cell: no zombies, and no safehouse, building, placing, pickup, scrapping or sledgehammer. Without it the cell is still walled, unpowered and has no zombie spawns. |

PhunTaxi ships a one cell map, **cell 87,49** (world x 22272 to 22527, y
12544 to 12799). Another map mod using that cell will conflict with it.

## Who counts as an admin

On a server, a player with the **Admin** or **Moderator** access level. The
server checks this again on every request, so hiding a menu is never the only
thing in the way.

In single player the admin tools are only offered in **debug mode**.

## Setting up a world

Walk the map and set up spawn points once, for this world and every world
after it. Open the [spawn point editor](#the-spawn-point-editor) and click
**Setup menu: off** to turn it on, then right click and open **Spawn point
setup**. It is off by default and off again the next time you play, so it
is not on every right click while you are just playing:

- **Add phone and spawn point here** puts one of our pay phones on the clicked
  square, facing you, and keeps it. Stand where a character should arrive and
  click the square **beside** you: the spawn point is in front of the phone,
  where you are standing. It is greyed out on your own square, and only
  offered where there is no phone yet.
- **Add just spawn point here** asks for a name and adds a spawn point on the
  clicked square. It starts as found by exploring; change that in the editor.
- **Store this payphone**, on any pay phone, keeps it. A vanilla phone is made
  live on the spot, whatever its roll said.

A pay phone you put down from the Taxi Phone item, or move with the movables
cheat, becomes a spawn point too, the first time anybody uses it or its square
loads. Like a player built phone it is not kept: store it if the next world
should have it.

Nothing checks that a square you add is free to stand on, so pick open floor.

With the setup menu on you also get **Spawn points** on any right click, which
opens the player's window as a map. An admin's **Go** works at any time, as a
teleport.

The phone guards (no pickup, rotate, dismantle, smash) do not apply in **admin
mode**, which is the movables cheat or the build cheat. That is a separate
switch from the setup menu. Turn it off to see what a player sees.

## The spawn point editor

Open it from the **admin panel** (Spawn point editor), or on single player
from the **debug menu** (PhunTaxi).

It lists every registered spawn point, found or not, with its region, how it
is found, where it is and how far it is from you, nearest first, beside the
whole map. Tabs filter by how a point is found (Start, Exploring, Pay phone,
Other), and Deleted holds the points you have deleted. Select a point to see it on the
map, then:

| Button | What it does |
|---|---|
| Go there | Takes you to the point. It does not unlock it for you, set your last choice or use up a new character's ride. |
| Rename | Changes what players see. The id never changes, because it is what every player's unlocks store. Players see the new name the next time they open their list. |
| Reset name | Puts back the name the point was registered with. |
| Keep / Release | On a pay phone. A kept phone is carried into the next world after a wipe. Released, it stays where it is but is not carried over. |
| Found by | On a point an admin added: each press steps it through known from the **start**, found by **exploring**, and only **granted** (by an admin or another mod). |
| Remove | On a point an admin added on a square: takes it out of `PhunTaxi.json` for good. |
| Delete | On any other point that is not a pay phone, shipped or another mod's: hides it from everybody, and it stays hidden through a reboot and a wipe. Nobody loses it from their list. The last start point cannot be deleted. |
| Restore | On a deleted point, in the Deleted tab: puts it back, with any rename it had, for everybody who had found it. |
| Setup menu | Not about the selected point: turns **Spawn point setup** and **Spawn points** on your right click on or off, for you only. Off each time you start playing. |

A pay phone is not deleted: release it, or take it down if it was built.

## PhunTaxi.json

Everything you set up is written straight away to `PhunTaxi.json` in the
server's Lua folder (`Zomboid/Lua/`, beside `PhunInteriors.json`):

- spawn points you added,
- pay phones you kept,
- every rename,
- every point you deleted.

That folder is not part of the save, so **a wipe leaves it alone**. In the new
world the points register at boot, and each kept phone is put back the first
time its square loads, replacing the vanilla phone standing there if there is
one. A kept phone that goes missing is put back the same way; release it
first if you want it gone.

The file is meant to be read and hand edited, and copying it to another
server copies the setup:

```json
{
  "version": 1,
  "points": {
    "phun.spawn.custom.10608_9698_0": {
      "label": "Muldraugh - Gas station", "region": "Muldraugh",
      "x": 10608, "y": 9698, "z": 0, "discovery": "start"
    }
  },
  "phones": {
    "11702_6890_0": { "x": 11702, "y": 6890, "z": 0, "facing": "E" }
  },
  "labels": { "phun.spawn.westpoint.motel": "The Motel" },
  "deleted": { "phun.spawn.riverside.marina": true }
}
```

- A point's `x, y, z` is where the character arrives. `discovery` is
  `start`, `explore` (the default) or `granted`.
- A point's `phone` (E, S, W or N) puts a pay phone of ours on the square
  **behind** `x, y`, facing that way, so the point is a taxi stop. It is put
  up when its square loads and put back if it goes. Every shipped point has
  one, so when you move a shipped point, give your copy a `phone` too, and
  check that the square behind it takes one.
- A point with the same id as a shipped one **replaces** it. That is how you
  move a shipped point that lands somewhere bad, without touching code.
- A phone's `x, y, z` is **the phone's own square**. `facing` (E, S, W or N)
  puts the traveller on the square in front of it.
- `labels` renames any point by id, shipped or added.
- `deleted` hides any point by id, shipped, another mod's or added. The code
  still registers it every boot and this keeps it out, so taking the line out
  (or Restore) brings it back as the code has it now.
- An entry that is wrong is left out and named in the server log. The rest
  still count.

**Edit it with the server stopped, or reload straight after.** Every change
made in game rewrites the file, so a hand edit made while the server runs is
lost at the next one unless it is read in first with
`PhunTaxi.admin("reload")`. A file that does not parse is never written over:
nothing is saved to it until it reads again, and the server log says so.

## Console commands

From the Lua console of a client logged in as an admin. The answer is printed
to that client's console.

| Command | What it does |
|---|---|
| `PhunTaxi.admin("list")` | Every registered point: id, region, position, how it is found. |
| `PhunTaxi.admin("where")` | Your own position, for writing into `PhunTaxi.json`. |
| `PhunTaxi.admin("grant", {id = "..."})` | Unlocks a point for you. Add `username = "..."` to unlock it for somebody online. |
| `PhunTaxi.admin("reload")` | Reads `PhunTaxi.json` again after a hand edit, and lists any problems in it. |
| `PhunTaxi.admin()` | Counts of what is registered. |

## What a wipe keeps

| | Survives a wipe | Where it lives |
|---|---|---|
| Points added from the setup menu or by hand | yes | `PhunTaxi.json` |
| Kept pay phones | yes | `PhunTaxi.json` |
| Renames | yes | `PhunTaxi.json` |
| Deleted points | yes | `PhunTaxi.json` |
| Players' unlocks and last choice | no | the world's global ModData |
| Live pay phones nobody kept | no, they are rolled again | the world's global ModData |
| Player built pay phones | no | the world's global ModData |

Players' unlocks are one record per **account** (the username), so a player's
exploring carries over to their next character but not into a new world.

## Things to know

- **The shipped spawn points** are Smokeys in Muldraugh, the Rosewood motel,
  the Riverside courthouse and the West Point picnic area, all known from the
  start. Each has a pay phone behind its arrival square, so a new character
  can call a taxi from wherever the free ride took them. Deleting one leaves
  its phone standing as an ordinary pay phone.
- **Somewhere has to be a start point.** A new player who knows nothing has
  nowhere to ride to. If you replace or delete the shipped ones, make sure
  something else is. The editor will not delete the last one.
- In single player the vanilla spawn selector still shows, because it runs in
  the main menu before PhunTaxi loads. A new character is moved into the Taxi
  Garage whatever was picked there.
- Turn on the **Debug** option for detailed logging of registration,
  discovery and spawning.
