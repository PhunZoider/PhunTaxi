if isClient() then
    return
end
require "PhunSpawn/points"
require "PhunSpawn/tools"
local Core = PhunSpawn
local Placement = {}

-- ---------------------------------------------------------------------------
-- Whether a character may still choose where to wake up.
--
-- The picker is a map of every place this character knows, and a button on
-- it that put you at any of them whenever you liked would be fast travel,
-- which makes discovering a place worth nothing once you have. So the button
-- works once, for a NEW character, and after that the picker is a map.
--
-- The state lives in the character's modData under consts.spawnedKey, for the
-- reason the unlocks do: it has to survive a rejoin, or a character could
-- reconnect for a second free choice.
--
--   nil        not looked at yet
--   "pending"  a new character who has not chosen
--   a number   world age hours when they were placed; 0 for a character who
--              was already established when PhunSpawn first saw them
--
-- "New" is decided ONCE, the first time the server looks, and stamped. A
-- character who takes an hour over the choice is still choosing, and one who
-- has survived for weeks before the mod was installed is not handed a free
-- teleport by the install.
-- ---------------------------------------------------------------------------

-- A character younger than this, in in game hours, when first seen is new.
-- Generous rather than exact, because the first look is at playerSetup, which
-- lands a few ticks after the character exists, not at the moment of creation.
local NEW_CHARACTER_HOURS = 1

function Placement.state(player)
    local md = player:getModData()
    local value = md[Core.consts.spawnedKey]
    if value == nil then
        if player:getHoursSurvived() < NEW_CHARACTER_HOURS then
            value = "pending"
        else
            value = 0
        end
        md[Core.consts.spawnedKey] = value
    end
    return value
end

function Placement.isPending(player)
    return Placement.state(player) == "pending"
end

--- May this character use the spawn button right now?
--
-- An admin may on a server, as a teleport tool. In single player tools.isAdmin
-- answers yes for everybody, which is right for admin commands and wrong here:
-- it would make the picker fast travel in every SP game. So SP asks for debug
-- mode instead, which is a deliberate choice somebody made at launch.
function Placement.canSpawn(player)
    if Placement.isPending(player) then
        return true
    end
    if Core.isLocal then
        return getDebug ~= nil and getDebug() == true
    end
    return Core.tools.isAdmin(player)
end

--- Record that the character has been placed. Only a pending character's
--- state moves: an admin porting about is not being placed, and stamping them
--- would overwrite when they actually were.
function Placement.markSpawned(player)
    if Placement.isPending(player) then
        player:getModData()[Core.consts.spawnedKey] = Core.now()
        return true
    end
    return false
end

Core.modules.placement = Placement
return Placement
