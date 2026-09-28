require "PhunSpawn/core"
require "PhunSpawn/points"
local Core = PhunSpawn

-- ---------------------------------------------------------------------------
-- The shipped spawn points.
--
-- Registered on our own OnRegisterPoints event, which is what a generated
-- file reads best on. A third party should hook Events.OnInitGlobalModData
-- instead: both routes work, but theirs cannot be broken by load order. See
-- README.md and interiors.lua for why.
--
-- These are vanilla Muldraugh coordinates and they are PLACEHOLDERS. Every
-- one needs checking against the map before it ships, because a spawn point
-- on a square that is solid, or inside a wall built since, drops a new
-- character into geometry and there is nothing here that can tell.
--
-- Sourced deliberately rather than by arithmetic: a set of points laid out on
-- a grid would be three lines shorter and would put half of them in the
-- river.
-- ---------------------------------------------------------------------------

Events[Core.events.OnRegisterPoints].Add(function()

    Core.registerPoint("phun.spawn.muldraugh.warehouse", {
        label = "Muldraugh - Warehouse",
        region = "Muldraugh",
        x = 10608,
        y = 9698,
        z = 0,
        -- Known from character creation: somewhere has to be, or a new
        -- character has nowhere at all to wake up.
        discovery = Core.discovery.start,
        priority = 0
    })

    Core.registerPoint("phun.spawn.westpoint.motel", {
        label = "West Point - Motel",
        region = "West Point",
        x = 11780,
        y = 6820,
        z = 0,
        discovery = Core.discovery.explore
    })

    Core.registerPoint("phun.spawn.riverside.marina", {
        label = "Riverside - Marina",
        region = "Riverside",
        x = 6540,
        y = 5250,
        z = 0,
        discovery = Core.discovery.explore
    })
end)

return Core
