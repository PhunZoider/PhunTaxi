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
-- Floor 14x9 (the garage 8x9, then office 6x5 over kitchen 4x4 and bathroom
-- 2x4), 64 slots, 8x8 across cell 87,49. Every location is the garage room
-- def read out of the lotheader with PhunInteriors' scripts/rooms.pl, not
-- laid out on a grid, and checked with its scripts/roomcheck.pl
-- (scripts/map.cmd runs it). Shared when full (server/arrival.lua).
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
            w = 15,
            h = 10
        },
        spawn = {
            x = 7,
            y = 3
        },
        selfPowered = true,
        -- Handed back when the last person in it leaves, by any route.
        -- Nobody comes back to their arrival room, and with the room shared
        -- when full (server/arrival.lua) PhunInteriors, not us, knows who
        -- is last.
        singleUse = true,
        generator = {
            x = 12,
            y = 1,
            z = 1
        },
        locations = {
            [0] = {22276, 12565, 0},
            [1] = {22307, 12565, 0},
            [2] = {22338, 12565, 0},
            [3] = {22369, 12565, 0},
            [4] = {22400, 12565, 0},
            [5] = {22431, 12565, 0},
            [6] = {22462, 12565, 0},
            [7] = {22493, 12565, 0},
            [8] = {22276, 12596, 0},
            [9] = {22307, 12596, 0},
            [10] = {22338, 12596, 0},
            [11] = {22369, 12596, 0},
            [12] = {22400, 12596, 0},
            [13] = {22431, 12596, 0},
            [14] = {22462, 12596, 0},
            [15] = {22493, 12596, 0},
            [16] = {22276, 12627, 0},
            [17] = {22307, 12627, 0},
            [18] = {22338, 12627, 0},
            [19] = {22369, 12627, 0},
            [20] = {22400, 12627, 0},
            [21] = {22431, 12627, 0},
            [22] = {22462, 12627, 0},
            [23] = {22493, 12627, 0},
            [24] = {22276, 12658, 0},
            [25] = {22307, 12658, 0},
            [26] = {22338, 12658, 0},
            [27] = {22369, 12658, 0},
            [28] = {22400, 12658, 0},
            [29] = {22431, 12658, 0},
            [30] = {22462, 12658, 0},
            [31] = {22493, 12658, 0},
            [32] = {22276, 12689, 0},
            [33] = {22307, 12689, 0},
            [34] = {22338, 12689, 0},
            [35] = {22369, 12689, 0},
            [36] = {22400, 12689, 0},
            [37] = {22431, 12689, 0},
            [38] = {22462, 12689, 0},
            [39] = {22493, 12689, 0},
            [40] = {22276, 12720, 0},
            [41] = {22307, 12720, 0},
            [42] = {22338, 12720, 0},
            [43] = {22369, 12720, 0},
            [44] = {22400, 12720, 0},
            [45] = {22431, 12720, 0},
            [46] = {22462, 12720, 0},
            [47] = {22493, 12720, 0},
            [48] = {22276, 12751, 0},
            [49] = {22307, 12751, 0},
            [50] = {22338, 12751, 0},
            [51] = {22369, 12751, 0},
            [52] = {22400, 12751, 0},
            [53] = {22431, 12751, 0},
            [54] = {22462, 12751, 0},
            [55] = {22493, 12751, 0},
            [56] = {22276, 12782, 0},
            [57] = {22307, 12782, 0},
            [58] = {22338, 12782, 0},
            [59] = {22369, 12782, 0},
            [60] = {22400, 12782, 0},
            [61] = {22431, 12782, 0},
            [62] = {22462, 12782, 0},
            [63] = {22493, 12782, 0}

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
