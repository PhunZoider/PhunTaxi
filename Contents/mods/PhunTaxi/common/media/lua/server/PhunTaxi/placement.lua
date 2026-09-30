if isClient() then
    return
end
require "PhunTaxi/points"
require "PhunTaxi/tools"
local Core = PhunTaxi
local Placement = {}

-- ---------------------------------------------------------------------------
-- Whether a character may still take the free ride.
--
-- The picker is a map of every place this character knows, and a button on
-- it that put you at any of them whenever you liked would be fast travel,
-- which makes discovering a place worth nothing once you have. So the button
-- works once, for a NEW character, and after that the picker is a map.
--
-- On a server that is WHERE THEY ARE, and nothing is stored. Every vanilla
-- spawn region collapses to a square in the Taxi Garage's cell (arrival.lua),
-- the garage has no way out but the taxi, and the taxi is the ride. So a
-- character standing in the cell is new, or rejoined still in the garage, and
-- one standing anywhere else has had their ride. Dying puts the next one back
-- on the landing square. A flag in player modData did this before and was
-- lost: a server side write to player modData does not persist on a server,
-- and the client's copy is the one saved.
--
-- Single player keeps the flag, because its selector runs in the main menu
-- before any of this loads and is never collapsed, so a new character starts
-- in a vanilla town; and there modData is saved where it is written. Under
-- consts.spawnedKey:
--
--   nil        not looked at yet
--   "pending"  a new character who has not chosen
--   a number   world age hours when they were placed; 0 for a character who
--              was already established when PhunTaxi first saw them
--
-- "New" is decided ONCE, the first time the server looks, and stamped. A
-- character who takes an hour over the choice is still choosing, and one who
-- has survived for weeks before the mod was installed is not handed a free
-- teleport by the install. A character in the garage is pending in single
-- player too, whatever the flag says.
-- ---------------------------------------------------------------------------

-- A character younger than this, in in game hours, when first seen is new.
-- Generous rather than exact, because the first look is at playerSetup, which
-- lands a few ticks after the character exists, not at the moment of creation.
local NEW_CHARACTER_HOURS = 1

--- Is the player standing in the Taxi Garage's cell?
function Placement.inGarage(player)
    local g = Core.consts.garage
    local x, y = player:getX(), player:getY()
    return x >= g.x1 and x < g.x2 + 1 and y >= g.y1 and y < g.y2 + 1
end

--- Single player's flag: see the top of the file.
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
    if Placement.inGarage(player) then
        return true
    end
    return Core.isLocal and Placement.state(player) == "pending"
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

--- Record that the character has been placed. Single player only: on a
--- server the ride out of the garage is the record. Only a pending
--- character's flag moves: an admin porting about is not being placed, and
--- stamping them would overwrite when they actually were.
function Placement.markSpawned(player)
    if Core.isLocal and Placement.state(player) == "pending" then
        player:getModData()[Core.consts.spawnedKey] = Core.now()
        return true
    end
    return false
end

Core.modules.placement = Placement
return Placement
