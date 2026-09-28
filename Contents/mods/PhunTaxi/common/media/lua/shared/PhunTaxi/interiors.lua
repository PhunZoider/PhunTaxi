require "PhunTaxi/core"
require "PhunTaxi/points"
local Core = PhunTaxi

-- ---------------------------------------------------------------------------
-- The PhunInteriors hook: a spawn ROOM.
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
-- on a dedicated server, and by the time it fires all lua has loaded, so
-- PhunInteriors' registry is there whichever mod loaded first.
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

--- Can PhunInteriors take a room registration?
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
-- One slot for now, shared when full (server/arrival.lua). Any more are read
-- out of the lotpacks with PhunInteriors' scripts/tiles.pl, not laid out on a
-- grid, and checked with its scripts/roomcheck.pl (scripts/map.cmd runs it).
function Core.registerRooms()
    -- A hard dependency, so this is only ever missing when PhunInteriors is
    -- older than this mod. Said loudly, as server_commands does for sendTo.
    if not Core.interiorsReady() then
        Core.logLn("PhunInteriors.registerRoom is missing; PhunInteriors is older than this version of PhunTaxi needs")
        return false
    end

    PhunInteriors.registerRoom(Core.roomIds.arrival, {
        label = "Spawn",
        source = "phuntaxi",
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

    return true
end

Events.OnInitGlobalModData.Add(function()
    -- All lua has loaded by now, so PhunInteriors' registry is there to take
    -- the room whatever order the two mods loaded in.
    Core.registerRooms()
end)

return Core
