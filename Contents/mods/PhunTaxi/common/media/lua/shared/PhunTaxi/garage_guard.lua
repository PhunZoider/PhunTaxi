require "PhunTaxi/core"
require "PhunTaxi/phone_guards"
local Core = PhunTaxi

-- ---------------------------------------------------------------------------
-- The Taxi Garage's doors out are scenery. The taxi is the only way out.
--
-- Two doors lead out of the building, onto the void: the roller door, and
-- the office's back door. The roller door's art is vanilla's
-- walls_garage_02_51 to _53, which carry doorN and GarageDoor, so the game
-- makes them a working IsoDoor when the square loads, and no vanilla sprite
-- has that look without them. Locking would not hold: vanilla lets anyone on
-- the inside of a building lock and unlock a door by hand, and the garage is
-- the inside. So the open itself is refused, for any shut door in the cell
-- with a room on one side only. Doors between the garage's rooms still work.
--
-- Every way vanilla opens a door from Lua (the context menu, a click, the
-- interact key, Viewpoint's [F] menu, which harvests the context menu) queues
-- ISOpenCloseDoor, and that is the one hook. SHARED for the same reason as
-- phone_guards: the server completes the action and asks isValid as it does.
-- An open door may still be closed. Admin mode is the phones' (the movables
-- or build cheat), so an admin setting up the garage turns it on to get out.
--
-- Not covered: hitting the door until it breaks. PhunZones' garage zone
-- blocks the sledgehammer; a weapon is not stopped by anything here.
-- ---------------------------------------------------------------------------

local installed = false

local NOTE_MS = 3000
local lastNote = 0

local function inGarageCell(square)
    local g = Core.consts.garage
    local x, y = square:getX(), square:getY()
    return x >= g.x1 and x <= g.x2 and y >= g.y1 and y <= g.y2
end

local function inRoom(square)
    return square ~= nil and square:getRoom() ~= nil
end

--- A shut door in the garage's cell that leads out of the building: a room
--- on one side and not on the other. The roller door, and the office's back
--- door, open onto the void; the doors between the garage's own rooms do not
--- and stay working.
local function isShutWayOut(object)
    if not (object and instanceof(object, "IsoDoor")) or object:IsOpen() then
        return false
    end
    local square = object:getSquare()
    if not (square and inGarageCell(square)) then
        return false
    end
    return not (inRoom(square) and inRoom(object:getOppositeSquare()))
end

local function refuse(character)
    if not character or not character.setHaloNote or isServer() then
        return
    end
    local now = getTimestampMs()
    if now - lastNote < NOTE_MS then
        return
    end
    lastNote = now
    character:setHaloNote(getText("IGUI_PhunTaxi_GarageDoorShut"), 255, 180, 60, 300)
end

function Core.installGarageGuard()
    if installed then
        return
    end
    installed = true

    if not ISOpenCloseDoor then
        Core.logLn("ISOpenCloseDoor not loaded; the garage door guard is off")
        return
    end
    local baseIsValid = ISOpenCloseDoor.isValid
    function ISOpenCloseDoor:isValid()
        if isShutWayOut(self.item) and not Core.phoneAdminMode(self.character) then
            refuse(self.character)
            return false
        end
        return baseIsValid(self)
    end
end

Events.OnInitGlobalModData.Add(Core.installGarageGuard)

return Core
