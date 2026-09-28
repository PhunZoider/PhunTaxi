if isServer() then
    return
end
require "PhunSpawn/taxi"
require "PhunSpawn/client_main"
local Core = PhunSpawn
local Client = Core.client

-- ---------------------------------------------------------------------------
-- The line over the taxi that tells a new character it is their way out.
--
-- The picker does not open by itself. A new character wakes up in the garage
-- and is pointed at the taxi instead, so the ride is something they walk up
-- to and take, and closing a window they never asked for is not the first
-- thing they do.
--
-- Drawn in screen space over the middle of the taxi's tiles, found by looking
-- around the player on a timer rather than by knowing where the room is: the
-- slot PhunInteriors hands out is its business, and the taxi is wherever the
-- map author stamped it.
--
-- Only while the server says this character is pending, and it stops for
-- good once they have been near a taxi and are not any more: that is the
-- ride having happened, and the payload saying so may be a while coming.
-- ---------------------------------------------------------------------------

-- How often to look for the taxi, and how far. The room is 9 by 10, so the
-- radius covers it from any square in it with room to spare.
local SCAN_TICKS = 30
local RADIUS = 12
-- Scans with no taxi found before giving up, for a character the server put
-- at a fallback point rather than in the room. About a minute at 60fps.
local GIVE_UP = 120
-- Floors above the taxi's own level to draw the line at: roughly its roof.
local LIFT = 1

local watching = false
local ticks = 0
local misses = 0
-- The middle of the taxi's tiles, {x, y, z}, or nil while none is in range.
local anchor = nil
local seen = false

--- The middle of every taxi tile within RADIUS of the player on their level,
--- or nil. The taxi is forty tiles; the average of their squares is its
--- middle whichever way round it was stamped.
local function findTaxi(player)
    local cell = getCell()
    if not cell then
        return nil
    end
    local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
    local sx, sy, count = 0, 0, 0
    for x = px - RADIUS, px + RADIUS do
        for y = py - RADIUS, py + RADIUS do
            local square = cell:getGridSquare(x, y, pz)
            if square then
                local objects = square:getObjects()
                for i = 0, objects:size() - 1 do
                    local sprite = objects:get(i):getSprite()
                    if sprite and Core.isTaxiTile(sprite:getName()) then
                        sx, sy, count = sx + x + 0.5, sy + y + 0.5, count + 1
                        break
                    end
                end
            end
        end
    end
    if count == 0 then
        return nil
    end
    return {
        x = sx / count,
        y = sy / count,
        z = pz
    }
end

-- A table so stop can be defined below the tick that calls it, and stop
-- needs the tick to remove it.
local Hint = {}

local function onTick()
    ticks = ticks + 1
    if ticks < SCAN_TICKS then
        return
    end
    ticks = 0

    local player = getPlayer()
    if not Client.pending or not player then
        Hint.stop()
        return
    end
    anchor = findTaxi(player)
    if anchor then
        seen = true
        misses = 0
    elseif seen then
        -- Was by the taxi and is not now: the ride happened.
        Hint.stop()
    else
        misses = misses + 1
        if misses >= GIVE_UP then
            Hint.stop()
        end
    end
end

local function onDraw()
    local player = getPlayer()
    if not (anchor and player) then
        return
    end
    local index = player:getPlayerNum()
    local x = isoToScreenX(index, anchor.x, anchor.y, anchor.z + LIFT)
    local y = isoToScreenY(index, anchor.x, anchor.y, anchor.z + LIFT)
    -- A slow pulse, so it reads as a prompt and not as part of the scenery.
    local alpha = 0.75 + 0.25 * math.sin(getTimestampMs() / 300)
    local text = getText("IGUI_PhunSpawn_TaxiOnTheHouse")
    local tm = getTextManager()
    -- A drop shadow, as vanilla's own floating debug text has, so it reads
    -- over a pale floor.
    tm:DrawStringCentre(UIFont.Medium, x + 1, y + 1, text, 0, 0, 0, alpha)
    tm:DrawStringCentre(UIFont.Medium, x, y, text, 1, 1, 0.6, alpha)
end

function Hint.stop()
    if not watching then
        return
    end
    watching = false
    anchor = nil
    Events.OnTick.Remove(onTick)
    Events.OnPreUIDraw.Remove(onDraw)
end

--- Start pointing at the taxi, if not already. Called for every payload that
--- says this character is pending; the first one starts it and the rest do
--- nothing.
function Client.watchTaxi()
    if watching then
        return
    end
    watching = true
    ticks = SCAN_TICKS
    misses = 0
    seen = false
    anchor = nil
    Events.OnTick.Add(onTick)
    Events.OnPreUIDraw.Add(onDraw)
end

return Client
