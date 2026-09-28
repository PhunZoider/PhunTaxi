require "PhunSpawn/core"
local Core = PhunSpawn

-- ---------------------------------------------------------------------------
-- Pay phones: which vanilla tiles get swapped, and for what.
--
-- The same idea as PhunMart's vending machines. A vanilla pay phone gets one
-- roll, the first time its square loads, at PhoneChance percent, and only if
-- no swapped phone already stands within PhoneDistance. A phone that wins is
-- replaced by one of ours, and ours is a spawn point: using it is how a
-- character comes to know it. The roll and the swap are server side, see
-- server/phone_swap.lua. This file is the shared half, because the client has
-- to recognise one of our phones to offer the context menu.
--
-- Keyed by FACING on both sides, so a target and a replacement are one line
-- each and neither has to know about the other:
--
--   targets  vanilla sprite -> "E" | "S" | "W" | "N"
--   sprites  facing -> our sprite, or a list of them to pick from at random
--
-- Adding a target is Core.addPhoneTarget(sprite, facing). Changing or adding
-- a replacement is Core.addPhoneSprite(facing, sprite). Both are safe from
-- any hook that runs before the first square loads.
-- ---------------------------------------------------------------------------

Core.phones = {
    targets = {
        ["street_decoration_01_38"] = "E",
        ["street_decoration_01_39"] = "S",
        ["street_decoration_01_46"] = "W",
        ["street_decoration_01_47"] = "N"
    },
    sprites = {
        E = "phuninteriors_01_16",
        S = "phuninteriors_01_17",
        W = "phuninteriors_01_18",
        N = "phuninteriors_01_19"
    },
    -- What an unused phone rings with, and for how long, in milliseconds.
    -- Ours, in scripts/PhunSpawn_Sounds.txt. It loops, so it is stopped when
    -- the time is up or the phone is answered, and each phone rings once a
    -- session. Real time rather than game time on purpose: ten game minutes
    -- is 25 seconds on a one hour day and ten minutes on a 24 hour one. Its
    -- distanceMax is 30, so PhoneRingRange (default 30) should stay at or
    -- under that: a ring further off is one nobody hears, and it still uses
    -- up that phone's ring for the session.
    ringSound = "PhunSpawn_PhoneRinging",
    ringMs = 30000,
    -- Where the character stands to use a phone, and so where they wake up
    -- when they spawn at one. The phone's own square is solid.
    front = {
        E = {1, 0},
        S = {0, 1},
        W = {-1, 0},
        N = {0, -1}
    }
}

local facings = {
    E = true,
    S = true,
    W = true,
    N = true
}

-- Reverse of `sprites`: our sprite -> facing. Rebuilt whenever a replacement
-- is added rather than on read, because it is read on every square load.
local ours = {}

local function rebuildOurs()
    ours = {}
    for facing, value in pairs(Core.phones.sprites) do
        if type(value) == "table" then
            for _, name in ipairs(value) do
                ours[name] = facing
            end
        else
            ours[value] = facing
        end
    end
end
rebuildOurs()

--- Make a vanilla sprite eligible for the swap. Facing is the way the tile
--- faces, which is what picks the replacement.
function Core.addPhoneTarget(sprite, facing)
    if type(sprite) ~= "string" or not facings[facing] then
        Core.logLn("addPhoneTarget needs a sprite name and one of E, S, W, N")
        return false
    end
    Core.phones.targets[sprite] = facing
    return true
end

--- Add a replacement for one facing. With `replace` true it becomes the only
--- one; otherwise it joins whatever is there and one is picked at random.
function Core.addPhoneSprite(facing, sprite, replace)
    if type(sprite) ~= "string" or not facings[facing] then
        Core.logLn("addPhoneSprite needs one of E, S, W, N and a sprite name")
        return false
    end
    local existing = Core.phones.sprites[facing]
    if replace or existing == nil then
        Core.phones.sprites[facing] = sprite
    elseif type(existing) == "table" then
        table.insert(existing, sprite)
    elseif existing ~= sprite then
        Core.phones.sprites[facing] = {existing, sprite}
    end
    rebuildOurs()
    -- A replacement added after boot is guarded like the rest. Before boot
    -- this finds no sprites loaded and does nothing, and the guards' own
    -- install catches it.
    if Core.hardenPhoneSprites then
        Core.hardenPhoneSprites()
    end
    return true
end

--- Every sprite of ours, as a set: name -> facing. A copy, so a caller
--- cannot edit the lookup behind rebuildOurs' back.
function Core.phoneSpriteSet()
    local out = {}
    for name, facing in pairs(ours) do
        out[name] = facing
    end
    return out
end

--- The facing of a vanilla sprite that is eligible for the swap, or nil.
function Core.phoneTargetFacing(spriteName)
    return spriteName and Core.phones.targets[spriteName] or nil
end

--- The facing of one of OUR phone sprites, or nil. Nil means "not a phone of
--- ours", which is the test the client menu and the square scan both use.
function Core.phoneFacing(spriteName)
    return spriteName and ours[spriteName] or nil
end

--- The replacement for a facing. `roll` picks from a list and is ZombRand in
--- game; it is a parameter so the spec can pick without one.
function Core.phoneSpriteFor(facing, roll)
    local value = Core.phones.sprites[facing]
    if type(value) == "table" then
        if #value == 0 then
            return nil
        end
        return value[(roll and roll(#value) or 0) + 1]
    end
    return value
end

--- The spawn point id of the phone on a square.
--
-- Built from the square and nothing else, which is what lets the client tell
-- a phone it knows from one it does not: a known phone is in its points
-- payload under exactly this id, and it can build the id from a square it
-- has loaded without being told anything about phones it has not used.
function Core.phonePointId(x, y, z)
    return "phun.spawn.phone." .. tostring(x) .. "_" .. tostring(y) .. "_" .. tostring(z or 0)
end

--- Which phone should ring: the nearest spot within `range` that has one of
--- our phones standing on it now and whose point is not in `knownIds`.
--
-- `spots` is key -> {x, y, z}, the squares the client has seen a phone on,
-- ours or vanilla. `standing(spot)` answers whether one of OURS is there
-- now, which is asked at ring time rather than trusted from load time: the
-- server's swap can land after the client loaded the square. It may also
-- return nil for "that square is gone", and the spot is then dropped.
function Core.phoneToRing(spots, knownIds, px, py, range, standing)
    if not spots or not range or range <= 0 then
        return nil
    end
    local limit = range * range
    local best, bestDistance
    for key, spot in pairs(spots) do
        local dx, dy = spot.x - px, spot.y - py
        local distance = (dx * dx) + (dy * dy)
        if distance <= limit and (not bestDistance or distance < bestDistance) then
            local ours = standing(spot)
            if ours == nil then
                spots[key] = nil
            elseif ours and not knownIds[Core.phonePointId(spot.x, spot.y, spot.z)] then
                best, bestDistance = spot, distance
            end
        end
    end
    return best
end

--- The square a character stands on to use a phone at x, y facing `facing`.
function Core.phoneFront(x, y, facing)
    local offset = Core.phones.front[facing] or {0, 0}
    return x + offset[1], y + offset[2]
end

return Core
