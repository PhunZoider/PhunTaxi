require "PhunTaxi/core"
require "PhunTaxi/points"
local Core = PhunTaxi

-- ---------------------------------------------------------------------------
-- The shipped spawn points.
--
-- Registered on our own OnRegisterPoints event, which is what a generated
-- file reads best on. A third party should hook Events.OnInitGlobalModData
-- instead: both routes work, but theirs cannot be broken by load order. See
-- README.md and interiors.lua for why.
--
-- Each one has been checked in game: the square is open floor, and the square
-- behind it, the way `phone` says, takes a pay phone. That phone is what
-- makes a start point somewhere a taxi can be called from and ridden to. A
-- point moved here needs both checked again, because nothing in code can
-- tell a wall from a floor.
--
-- Sourced deliberately rather than by arithmetic: a set of points laid out on
-- a grid would be three lines shorter and would put half of them in the
-- river.
-- ---------------------------------------------------------------------------

Events[Core.events.OnRegisterPoints].Add(function()

    Core.registerPoint("phun.spawn.muldraugh.smokeys", {
        label = "Muldraugh - Smokeys",
        region = "Muldraugh",
        x = 10629,
        y = 9230,
        z = 0,
        -- Known from character creation: somewhere has to be, or a new
        -- character has nowhere at all to wake up.
        discovery = Core.discovery.start,
        priority = 0,
        -- The phone behind the arrival square, so the taxi can be called here.
        phone = "E"
    })

    Core.registerPoint("phun.spawn.rosewood.motel", {
        label = "Rosewood - Motel",
        region = "Rosewood",
        x = 8190,
        y = 11505,
        z = 0,
        -- Known from character creation: somewhere has to be, or a new
        -- character has nowhere at all to wake up.
        discovery = Core.discovery.start,
        priority = 0,
        -- The phone behind the arrival square, so the taxi can be called here.
        phone = "S"
    })

    Core.registerPoint("phun.spawn.riverside.courthouse", {
        label = "Riverside - Courthouse",
        region = "Riverside",
        x = 6491,
        y = 5459,
        z = 0,
        -- Known from character creation: somewhere has to be, or a new
        -- character has nowhere at all to wake up.
        discovery = Core.discovery.start,
        priority = 0,
        -- The phone behind the arrival square, so the taxi can be called here.
        phone = "S"
    })

    Core.registerPoint("phun.spawn.westpoint.picnic", {
        label = "West Point - Picnic Area",
        region = "West Point",
        x = 11622,
        y = 6634,
        z = 0,
        -- Known from character creation: somewhere has to be, or a new
        -- character has nowhere at all to wake up.
        discovery = Core.discovery.start,
        priority = 0,
        -- The phone behind the arrival square, so the taxi can be called here.
        phone = "E"
    })

end)

return Core
