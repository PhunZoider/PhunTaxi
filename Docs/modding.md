# Adding spawn points from another mod

Spawn points are registered, not hard coded. A mod or map can add its own,
and they appear in players' lists like any other.

An admin who only wants to add or move points does not need any of this: see
[Running a server](admin.md), which covers the in game setup menu and
`PhunTaxi.json`.

## Registering a point

Hook a **vanilla** event, not one of ours, and register from inside it:

```lua
Events.OnInitGlobalModData.Add(function()
    if not PhunTaxi then return end          -- definitive by now
    PhunTaxi.registerPoint("theirmod.lighthouse", {
        label  = "Lighthouse",
        region = "Riverside",
        x = 6100, y = 5200, z = 0,
        discovery = "explore",
    })
end)
```

Put it in `media/lua/shared/`, so the server and every client register the
same points.

### Why this hook

- `Events.OnInitGlobalModData` always exists, so where your file falls in the
  load order cannot break the `.Add`.
- By the time it fires every Lua file has loaded, so `PhunTaxi` is either
  there or genuinely not installed. The nil check is an answer, not a race.
- **Not `OnGameStart`.** It only fires from `IngameState`, which a dedicated
  server does not have, so a point registered there exists on every client
  and on no server.
- **Not `if PhunTaxi then ... end` at the top of your file.** That works when
  PhunTaxi happens to load first and silently does nothing when it does not.
  The nil check belongs inside the handler.

Registering late is fine. The indexes rebuild on the first read after any
registration, so a point that turns up after PhunTaxi has booted is picked
up the moment it arrives.

PhunTaxi also fires its own `PhunTaxiOnRegisterPoints` event, which is what
its shipped points use. It works, but the vanilla hook is the one nobody can
get wrong.

## The definition

| Field | | What it is |
|---|---|---|
| `label` | required | What players see. An admin can rename it; your id never changes. |
| `x`, `y` | required | The square the character arrives on. Pick open floor: nothing checks it, and a point on a wall drops a character into geometry. |
| `z` | default 0 | The level. |
| `region` | optional | Free text. Points are grouped under it in the player's list. Points with none go under "Elsewhere". |
| `discovery` | default `explore` | How it is found; see below. |
| `priority` | default 0 | Lower sorts first within a region. |
| `room` | optional | A PhunInteriors room id to arrive inside. **Not used yet**: stored, and ignored. |
| `phone` | optional | `E`, `S`, `W` or `N`. A pay phone of PhunTaxi's stands on the square **behind** `x, y`, facing that way, so the point is somewhere a taxi can be called from and ridden to. The server puts it up when its square loads and puts it back if it goes. Using it grants your point. The square behind has to take a phone: check it in game. |
| `mods` | optional | A list of mod ids, eg `{"somemap", "somemaptest"}`. The point exists only when **at least one** of them is active. Otherwise it is not registered at all, and a `phone` it asks for never goes up. Leave it out, or pass `{}`, for a point that is always there. |

`registerPoint` returns the point. It returns nil, with a line in the log,
if the definition is missing something, and nil without registering
anything if none of its `mods` is active.

### The id

The id is what every player's unlock list stores, so:

- **Namespace it** with your mod's name (`yourmod.something`). Ours are
  `phun.spawn.*`. Every mod shares one registry.
- **Never change it** once players have found it. A point that disappears is
  filtered out of lists, not deleted from them, so putting the same id back
  restores it to everybody who had it.
- Registering an id again replaces the point, with a line in the log.

### How a point is found

| `discovery` | Found by |
|---|---|
| `explore` | Getting within the server's Place Discovery Range. **The default**, because the safe default is the one that gives nothing away: a point everybody should know has to say so. |
| `start` | Nothing: every player knows it from their first character. Granted when read, so a start point added in a later version of your mod reaches existing players. |
| `granted` | Only by being granted, by an admin or by code (below). |
| `used` | Picking up a pay phone. Reserved for PhunTaxi's own phones. To have a player find your point by its phone, give it a `phone` and leave `discovery` as `explore` or `granted`: picking up that phone grants it. |

## Granting a point

Server side only, where the unlock lists live:

```lua
local Unlocks = PhunTaxi.modules.unlocks
if Unlocks then
    Unlocks.grant(player, "theirmod.lighthouse")   -- true if it was new
end
```

It returns true only when something changed, so you can use it to decide
whether to tell the player. `Unlocks.has(player, id)` and
`Unlocks.revoke(player, id)` are beside it.

`PhunTaxi.modules` is filled as the server files load, so look it up when
you use it rather than at the top of your file.

## Removing a point

```lua
PhunTaxi.removePoint("theirmod.lighthouse")
```

It leaves players' unlock lists alone. Registering the id again later brings
it back for everyone who had found it.

An admin can delete your points too, from the editor. That is a tombstone
in their `PhunTaxi.json`: your code still registers the id, and it is kept
out of the registry until they restore it. Nothing on your side needs to
handle it, and `PhunTaxi.points[id]` is nil for a deleted point as for a
removed one.

## Shipping pay phones

A mod can ship kept pay phones, which every world has: add entries in
`PhunTaxi.json`'s own shape to `PhunTaxi.shipped` while your files load,
before `OnInitGlobalModData`.

```lua
table.insert(PhunTaxi.shipped, {
    x = 6100, y = 5201, z = 0, facing = "N",
    label = "Lighthouse phone",
    mods = {"somemap"}
})
```

`x, y, z` is where the traveller stands and `facing` puts the phone on the
square behind, so a line can be copied out of a `PhunTaxi.json`. An entry
with only an `id` and a `label` names a phone that is not kept. `mods` keeps
the phone only when one of those mods is active. Points are not shipped this
way: register them with `registerPoint`. An admin's file overrides all of it,
and both squares need checking in game, as for a point's `phone`. PhunTaxi
does not ship its own phones this way: they are spots (below), so a world
gets one per town rather than all of them.

## Events

Registered with `Events.<name>.Add(fn)`. Look the event up inside your
`OnInitGlobalModData` handler, for the same reason as above.

| Event | Side | Arguments | When |
|---|---|---|---|
| `PhunTaxiOnRegisterPoints` | both | `PhunTaxi` | Registration opens, once per boot. |
| `PhunTaxiOnReady` | both | `PhunTaxi` | After registration, once the mod has booted. |
| `PhunTaxiOnPointUnlocked` | server | `player, point` | A player found a point or was granted one. |
| `PhunTaxiOnSpawned` | server | `player, point` | A new character was placed at a point. |

## Pay phone spots

For a stretch of your map with no vanilla pay phone, offer squares where one
of PhunTaxi's may go:

```lua
Events.OnInitGlobalModData.Add(function()
    if not PhunTaxi then
        return
    end
    -- x, y, z of the PHONE, the way it faces, and optionally a percent
    -- chance, 1 to 100
    PhunTaxi.addPhoneCandidate(10500, 9000, 0, "S")
    PhunTaxi.addPhoneCandidate(10620, 9080, 0, "E")
    PhunTaxi.addPhoneCandidate(10700, 8950, 0, "W", 50)
    -- a sixth argument lists mods, at least one of which must be active
    PhunTaxi.addPhoneCandidate(10800, 9010, 0, "N", nil, {"somemap"})
end)
```

A spot with `mods` is offered only while at least one of them is active.
If none is, `addPhoneCandidate` adds nothing and returns false. When a
server drops the mod, a spot whose phone has not gone up yet is dropped
like any spot taken out, and one whose phone is already standing stays.

Each world draws every spot once, in a random order. A spot is used only if
it is at least the server's Pay Phone Spacing from every phone already drawn
or standing, so several spots closer together than that give one phone,
chosen at random. A `chance` below 100 means the spot can pass up its turn,
and then the gap can have none. The phone goes up the first time its square
loads, and after that it is an ordinary pay phone, found by using it.

Unlike a point's `phone`, `x, y` here is the phone's own square, and the
traveller stands on the square in front of it, so check both in game. A spot
you take out of your mod before its phone has gone up is dropped. One whose
phone is already standing stays standing.

## Map authors

A point is data, not arithmetic. If you have a regular set of points, write
the loop in your own file; there is deliberately no "origin plus spacing"
form, because a grid of points is three lines shorter and puts half of them
in the river.

The Taxi Garage map itself, and how it is built, is in [map.md](map.md).
