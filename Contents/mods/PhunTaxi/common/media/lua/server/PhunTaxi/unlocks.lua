if isClient() then
    return
end
require "PhunSpawn/points"
require "PhunSpawn/tools"
local Core = PhunSpawn
local Unlocks = {}

-- ---------------------------------------------------------------------------
-- What a player knows about.
--
-- The truth is one record per ACCOUNT in global ModData, keyed by
-- Core.accountKey: {unlocked = {pointId = true}, lastChoice = pointId}.
-- Core.unlocked is a server side cache of the unlocked half, keyed the same
-- way and rebuilt on login, so a lookup does not reach into ModData every
-- time somebody moves.
--
-- Per account because an unlock is only worth anything at the moment of
-- choosing where to wake up, and that moment belongs to the NEXT character.
-- See consts.accountsKey.
--
-- Server side because it is the authority. A client that simply declines to
-- run the discovery check must still not be able to pick a point it has not
-- found, so every read that decides anything goes through here and the client
-- copy is only ever for drawing.
-- ---------------------------------------------------------------------------

--- The account record, created on first use.
--
-- Also where the per character lists of older versions come home. Anything a
-- character's modData still holds is folded in and then cleared, so it is
-- read once and a later character on the same account inherits it. Cleared
-- rather than kept as a second copy, because two lists that each look like
-- the truth will disagree.
local function account(player)
    local key = Core.accountKey(player)
    Core.data[Core.consts.accountsKey] = Core.data[Core.consts.accountsKey] or {}
    local accounts = Core.data[Core.consts.accountsKey]
    local rec = accounts[key]
    if not rec then
        rec = {unlocked = {}}
        accounts[key] = rec
    end
    rec.unlocked = rec.unlocked or {}

    local md = player:getModData()
    local legacy = md[Core.consts.unlockedKey]
    if legacy then
        for id in pairs(legacy) do
            rec.unlocked[id] = true
        end
        md[Core.consts.unlockedKey] = nil
    end
    if md[Core.consts.lastChoiceKey] then
        rec.lastChoice = rec.lastChoice or md[Core.consts.lastChoiceKey]
        md[Core.consts.lastChoiceKey] = nil
    end
    return rec
end

local function record(player)
    return account(player).unlocked
end

--- Where this player last chose to wake up, or nil.
function Unlocks.lastChoice(player)
    return account(player).lastChoice
end

function Unlocks.setLastChoice(player, pointId)
    account(player).lastChoice = pointId
end

--- Load a player's list into the cache and return it.
--
-- Points that no longer exist are filtered on READ rather than deleted, which
-- is why removePoint does not have to walk every account. Removing a point
-- set temporarily and putting it back costs nobody their exploring.
function Unlocks.load(player)
    local key = Core.accountKey(player)
    if not key then
        return {}
    end
    local stored = record(player)
    local live = {}
    for id in pairs(stored) do
        if Core.points[id] then
            live[id] = true
        end
    end
    -- The starters are granted on read rather than stamped once at character
    -- creation. A point added to the start set in a later version then
    -- reaches existing characters, and there is no migration to write.
    for id, point in pairs(Core.points) do
        if point.discovery == Core.discovery.start then
            live[id] = true
        end
    end
    Core.unlocked[key] = live
    return live
end

function Unlocks.has(player, pointId)
    local key = Core.accountKey(player)
    if not key then
        return false
    end
    -- The registry is asked first, and not just the cache. A point removed
    -- since the cache was built is still sitting in it, so trusting the cache
    -- alone would report a place nobody can go as known, and the failure
    -- would land at the moment somebody picked it. This is the same filter
    -- Unlocks.load applies; it has to be here too, because the cache outlives
    -- a registration change and nothing invalidates it.
    if not Core.points[pointId] then
        return false
    end
    local live = Core.unlocked[key] or Unlocks.load(player)
    return live[pointId] == true
end

--- Grant a point. Returns true only when something actually changed, so a
--- caller can use the return value to decide whether to tell the player.
function Unlocks.grant(player, pointId)
    local point = Core.points[pointId]
    if not point then
        return false
    end
    if Unlocks.has(player, pointId) then
        return false
    end

    record(player)[pointId] = true
    local key = Core.accountKey(player)
    Core.unlocked[key] = Core.unlocked[key] or {}
    Core.unlocked[key][pointId] = true

    triggerEvent(Core.events.OnPointUnlocked, player, point)
    Core.debugLn(tostring(key) .. " unlocked " .. pointId)
    return true
end

function Unlocks.revoke(player, pointId)
    if not Unlocks.has(player, pointId) then
        return false
    end
    record(player)[pointId] = nil
    local key = Core.accountKey(player)
    if Core.unlocked[key] then
        Core.unlocked[key][pointId] = nil
    end
    return true
end

--- Is this character standing close enough to an undiscovered point to have
--- found it? Returns the point that was unlocked, or nil.
--
-- Squared distance against a squared radius, so nothing needs a square root.
--
-- Explore points always, within DiscoveryRadius. Pay phones only when
-- PhoneDiscoverRadius is above zero, and it is meant to be small: it stands
-- in for walking up to the phone, not for passing the street it is on. A
-- phone's point is the square in front of it, so the radius is measured from
-- where a caller would stand.
function Unlocks.checkDiscovery(player)
    if not player then
        return nil
    end
    local x, y, z = player:getX(), player:getY(), player:getZ()
    local kinds = {{Core.discovery.explore, Core.settings.DiscoveryRadius or 0}}
    local phoneRadius = Core.settings.PhoneDiscoverRadius or 0
    if phoneRadius > 0 then
        table.insert(kinds, {Core.discovery.used, phoneRadius})
    end
    for _, kind in ipairs(kinds) do
        local point, distance = Core.nearestPoint(x, y, z, kind[1])
        if point and distance <= (kind[2] * kind[2]) and Unlocks.grant(player, point.id) then
            return point
        end
    end
    return nil
end

--- What to send a client: every point it may see, flagged with whether this
--- character has it.
--
-- The payload carries the coordinates of an undiscovered point only when
-- ShowUndiscovered says so. That is not tidiness: a client that is handed the
-- position can draw it whatever the option says, so the option has to be
-- honoured on this side or it is not honoured at all.
--
-- A pay phone nobody has used is left out even when ShowUndiscovered is on.
-- ShowUndiscovered makes the list somewhere to head for, and a phone is not a
-- destination: there can be hundreds, each one is only a phone, and a row per
-- phone would bury the places that are.
function Unlocks.payloadFor(player)
    local live = Unlocks.load(player)
    local out = {}
    for _, point in ipairs(Core.sortedPoints()) do
        local known = live[point.id] == true
        if known or (Core.settings.ShowUndiscovered and point.discovery ~= Core.discovery.used) then
            table.insert(out, {
                id = point.id,
                label = point.label,
                region = point.region,
                known = known,
                -- A pay phone, so the taxi can list only phones. Only ever
                -- true on a known point, since an unused phone is left out.
                phone = point.discovery == Core.discovery.used or nil,
                x = known and point.x or nil,
                y = known and point.y or nil,
                z = known and point.z or nil
            })
        end
    end
    return out
end

Core.modules.unlocks = Unlocks
return Unlocks
