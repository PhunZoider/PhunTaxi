if isServer() then
    return
end
require "PhunTaxi/client_main"
require "PhunTaxi/client_phone"
require "PhunTaxi/phones"
local Core = PhunTaxi
local Client = Core.client

-- ---------------------------------------------------------------------------
-- Placing a built phone: vanilla's build cursor, so the phone follows the
-- mouse as a ghost, R (Rotate Building) turns it, and it shows red where it
-- cannot go.
--
-- The kit stays what it is, not a moveable. Placing hands the square and the
-- facing to Client.queueBuildPhone, which walks to the front square and asks
-- the server, and the server checks everything again before anything is put
-- in the world (server/building.lua). What is checked here is only what the
-- client can see, so a green ghost can still be refused: the limit, spacing
-- and safehouses are the server's to know.
--
-- The ghost is drawn from the shared sprite rather than a fresh IsoSprite as
-- vanilla's render does, because the 3D model (media/spriteModels.txt) hangs
-- off the shared one, and a ghost in the wrong orientation would be worse
-- than a flat one.
--
-- ISBuildingObject is vanilla server code (media/lua/server/BuildingObjects),
-- which loads after client files and cannot be required from one: the class
-- is built on first use instead, when it is long since loaded.
-- ---------------------------------------------------------------------------

-- Vanilla's nSprite slots, 1 to 4, as R steps through them and as dragging
-- with the button held picks them: 1 west, 2 north, 3 east, 4 south.
local FACINGS = {"W", "N", "E", "S"}

local function standable(square)
    return square ~= nil and square:getFloor() ~= nil and not square:isSolid() and not square:isSolidTrans()
end

local function hasPhone(square)
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local sprite = objects:get(i):getSprite()
        local name = sprite and sprite:getName()
        if name and (Core.phoneFacing(name) or Core.phoneTargetFacing(name)) then
            return true
        end
    end
    return false
end

local Cursor = nil

local function cursorClass()
    if Cursor then
        return Cursor
    end
    Cursor = ISBuildingObject:derive("PhunTaxiPhoneCursor")

    function Cursor:facing()
        return FACINGS[self.nSprite] or "S"
    end

    function Cursor:getSprite()
        self.north, self.south, self.east, self.west = false, false, false, false
        self.chosenSprite = Core.phoneSpriteFor(self:facing())
        return self.chosenSprite
    end

    --- What the server checks that the client can see: floor and nothing
    --- solid on the phone's square and the one in front, no phone there
    --- already, the player's own level.
    function Cursor:isValid(square)
        local player = getSpecificPlayer(self.player)
        if not square or not player or square:getZ() ~= math.floor(player:getZ()) then
            return false
        end
        if not standable(square) or hasPhone(square) or square:isVehicleIntersecting() then
            return false
        end
        local fx, fy = Core.phoneFront(square:getX(), square:getY(), self:facing())
        return standable(getCell():getGridSquare(fx, fy, square:getZ()))
    end

    function Cursor:render(x, y, z, square)
        local sprite = getSprite(self:getSprite())
        if not sprite then
            return
        end
        if self:isValid(square) then
            sprite:RenderGhostTile(x, y, z)
        else
            sprite:RenderGhostTileRed(x, y, z)
        end
    end

    function Cursor:tryBuild(x, y, z)
        local player = getSpecificPlayer(self.player)
        getCell():setDrag(nil, self.player)
        local square = getCell():getGridSquare(x, y, z)
        -- Looked up again: the one the cursor was opened with may have been
        -- dropped or used in the meantime.
        local kit = player and player:getInventory():getFirstTypeRecurse(Core.consts.phoneKitItem)
        if square and kit then
            Client.queueBuildPhone(player, square, self:facing(), kit)
        end
    end

    function Cursor:new(playerNum)
        local o = ISBuildingObject.new(self)
        o:init()
        o.player = playerNum
        o.skipBuildAction = true
        o.dragNilAfterPlace = true
        o.noNeedHammer = true
        o.nSprite = 4
        return o
    end

    return Cursor
end

--- Pick up the cursor for this player, with the phone facing south to start.
function Client.startBuildCursor(player)
    if not player then
        return
    end
    getCell():setDrag(cursorClass():new(player:getPlayerNum()), player:getPlayerNum())
end

return Client
