require "PhunSpawn/core"
local Core = PhunSpawn

-- ---------------------------------------------------------------------------
-- The taxi, the shared half: what a ride costs and what a taxi tile is.
--
-- Shared because both sides need the same answer. The client shows the fare
-- on the Go button before anybody presses it, and the server charges it; two
-- copies of the sum would come to disagree, and the player would be charged
-- a different amount from the one they agreed to.
--
-- The rides themselves are server/taxi.lua.
-- ---------------------------------------------------------------------------

-- The taxi tiles, phuninteriors_02_0 to _39, which stand in the spawn room.
local TAXI_SHEET = "phuninteriors_02_"
local TAXI_LAST = 39

--- Is this sprite name one of the taxi tiles?
function Core.isTaxiTile(name)
    if type(name) ~= "string" or name:sub(1, #TAXI_SHEET) ~= TAXI_SHEET then
        return false
    end
    local index = tonumber(name:sub(#TAXI_SHEET + 1))
    return index ~= nil and index >= 0 and index <= TAXI_LAST and index == math.floor(index)
end

--- The fare, in cents, from one square to another: TaxiCentsPerSquare per
--- square in a straight line, rounded up, and never less than
--- TaxiMinimumFare. Zero when both settings are zero.
function Core.taxiFare(fromX, fromY, toX, toY)
    local perSquare = Core.settings.TaxiCentsPerSquare or 0
    local minimum = Core.settings.TaxiMinimumFare or 0
    local dx, dy = toX - fromX, toY - fromY
    local fare = math.ceil(math.sqrt(dx * dx + dy * dy) * perSquare)
    if fare < minimum then
        fare = minimum
    end
    return fare
end

--- Cents as money: 1234 is "$12.34".
function Core.formatCents(cents)
    cents = math.floor(cents or 0)
    return string.format("$%d.%02d", math.floor(cents / 100), cents % 100)
end

return Core
