require "PhunTaxi/core"
require "PhunTaxi/phones"
local Core = PhunTaxi

-- ---------------------------------------------------------------------------
-- The shipped pay phone candidates: squares a phone MAY go on, for the parts
-- of the map with no vanilla phone to swap.
--
-- Each world draws them once, in a random order, and a candidate goes up only
-- if it is at least PhoneDistance from every phone already drawn or recorded.
-- So put several round one gap, closer to each other than PhoneDistance, and
-- each world gets one of them, a different one each time. A candidate on its
-- own always goes up. See server/phone_swap.lua.
--
-- Each line is the PHONE's square, then the way it faces, which puts the
-- character on the square in front of it (Core.phoneFront). Both squares
-- have to be checked in game, as for a point's `phone`: nothing in code can
-- tell a wall from a floor. An optional fifth value is the percent chance it
-- is drawn at all, for a gap that should sometimes have nothing, and
-- `mods = {...}` offers the square only when at least one of those mods is
-- active, for a gap that is only there on a map mod's streets.
--
-- Sourced by hand, like defaults.lua, and not laid out by arithmetic.
-- ---------------------------------------------------------------------------

local candidates = {
    -- {x, y, z, facing[, chance][, mods = {"somemap"}]}
}

for _, c in ipairs(candidates) do
    Core.addPhoneCandidate(c[1], c[2], c[3], c[4], c[5], c.mods)
end

return Core
