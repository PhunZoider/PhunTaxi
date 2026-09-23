require "PhunSpawn/core"
require "PhunSpawn/points"
local Core = PhunSpawn

-- ---------------------------------------------------------------------------
-- The PhunInteriors hook: a spawn ROOM.
--
-- A soft hook and never a dependency. mod.info carries no require line, every
-- call in here is guarded, and with PhunInteriors absent the mod is a spawn
-- point picker that puts you on the square. That is a real fallback rather
-- than a broken feature, which is the only kind of optional integration worth
-- having.
--
-- Why a room at all: a character who wakes up on a kerb wakes up in whatever
-- is standing on it. A room is off grid, so the first thirty seconds of a new
-- character are theirs.
--
-- Registering on Events.OnInitGlobalModData rather than on one of
-- PhunInteriors' own events, and that is the rule to copy rather than the
-- exception. `Events` is a plain Kahlua table with no metatable, so a key
-- exists only once LuaEventManager.AddEvent has been called for it. If this
-- file loads before PhunInteriors' core.lua, `Events[theirs]` is nil and the
-- .Add throws. OnInitGlobalModData always exists, fires everywhere including
-- on a dedicated server, and by the time it fires all lua has loaded, so the
-- nil check below is decisive rather than a race.
--
-- It must NOT be OnGameStart: that is triggered only from
-- zombie.gameStates.IngameState, which a dedicated server does not have, so a
-- room registered there would exist on every client and on no server.
-- ---------------------------------------------------------------------------

-- Our own room ids, namespaced. Nothing parses one; they are keys.
Core.roomIds = {
    -- The room a new character wakes up in. One design, stamped wherever the
    -- map author put it.
    arrival = "phun.spawn.arrival"
}

--- Is PhunInteriors present and far enough through booting to talk to?
function Core.interiorsReady()
    return PhunInteriors ~= nil and PhunInteriors.registerRoom ~= nil
end

--- Register the arrival room with PhunInteriors.
--
-- Deliberately registers the ROOM and no binding. A binding says which
-- vehicles or objects may lease a room, and nothing leases this one: a spawn
-- room is entered by being a new character, which is a different question
-- from the entitlement machinery and must not be squeezed into it.
--
-- TODO: this ships no `locations`, because there is no map yet. A room with
-- no stamps registers and allocates nothing, which is the honest state of
-- affairs. Fill it from the map once the cells exist, reading the origins out
-- of the lotpacks with PhunInteriors' scripts/tiles.pl rather than off a grid.
function Core.registerRooms()
    if not Core.interiorsReady() then
        Core.debugLn("PhunInteriors is not installed, so spawn rooms are off")
        return false
    end

    PhunInteriors.registerRoom(Core.roomIds.arrival, {
        label = "Spawn",
        source = "phunspawn",
        size = {
            w = 9,
            h = 10
        },
        spawn = {
            x = 4,
            y = 7
        },
        selfPowered = true,
        -- Handed back when the last person in it leaves, by any route.
        -- Nobody comes back to their arrival room, and with the room shared
        -- when full (server/arrival.lua) PhunInteriors, not us, knows who
        -- is last.
        singleUse = true,
        generator = {
            x = 13,
            y = -6,
            z = 1
        },
        locations = {
            [0] = {22276, 12565, 0}
        }
    })

    PhunInteriors.registerVehicles({
        id = "phunspawn.vehicles.Spawn",
        source = "phunspawn",
        rooms = {"phun.spawn.arrival"},
        scripts = {"Base.CarTaxi"}
    })

    return true
end

Events.OnInitGlobalModData.Add(function()
    -- Definitive by now: all lua has loaded, so PhunInteriors either exists
    -- or genuinely is not installed.
    Core.registerRooms()
end)

return Core
