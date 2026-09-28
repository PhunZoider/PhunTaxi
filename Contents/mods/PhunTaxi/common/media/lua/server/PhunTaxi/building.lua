if isClient() then
    return
end
require "PhunSpawn/points"
require "PhunSpawn/phones"
require "PhunSpawn/tools"
local Core = PhunSpawn
local Unlocks = require "PhunSpawn/unlocks"
local PhoneSwap = require "PhunSpawn/phone_swap"
local Rides = require "PhunSpawn/rides"
local Building = {}

-- ---------------------------------------------------------------------------
-- Pay phones a player builds, from a crafted kit.
--
-- The kit is not a moveable. Building is a request the server checks in full
-- BEFORE anything is put in the world, and a refusal leaves the kit in the
-- player's hands. Going through vanilla's moveable placement instead would
-- put the object down first and leave us to take it back up, which is the
-- wrong order for a phone somebody could be using as a trap.
--
-- A built phone is a phone record like a swapped one, with `owner` (the
-- builder's account key) and `built` on it. So it registers, rings, is found
-- and is guarded exactly as the others are, and it is spaced against every
-- phone, swapped, kept or built. It is NOT in the store file: a wipe takes it
-- with the world it was built in.
--
-- Anywhere is allowed, indoors too, with one exception: not in a safehouse
-- the builder does not belong to. A phone in one's OWN safehouse is fine,
-- because it cannot be used against anybody: every ride, the first one and a
-- taxi, is refused into a safehouse the traveller does not belong to
-- (Rides.safehouseBlocks), so strangers never arrive. That arrival check is
-- the real protection. The build check only stops a phone going up where its
-- builder could not stand.
-- ---------------------------------------------------------------------------

local REACH = 2

--- How many phones this account has standing.
function Building.count(key)
    local n = 0
    for _, record in pairs(PhoneSwap.store()) do
        if record.owner == key then
            n = n + 1
        end
    end
    return n
end

--- Whether this player may build a phone at x, y, z, as far as can be told
--- without the square: the setting, their limit, the spacing and
--- safehouses. Returns nil, or a translation key and what it names.
function Building.refusal(player, x, y, z)
    if not Core.settings.AllowBuiltPoints then
        return "IGUI_PhunSpawn_BuiltPointsOff"
    end
    local limit = Core.settings.BuiltPointLimit or 0
    if limit > 0 and Building.count(Core.accountKey(player)) >= limit then
        return "IGUI_PhunSpawn_BuiltPointLimit", tostring(limit)
    end
    if not PhoneSwap.farEnough(x, y, Core.settings.BuiltPhoneDistance or 0) then
        return "IGUI_PhunSpawn_PhoneTooClose", tostring(Core.settings.BuiltPhoneDistance or 0)
    end
    if Rides.safehouseBlocks(player, x, y) then
        return "IGUI_PhunSpawn_NotYourSafehouse"
    end
    return nil
end

local function standable(square)
    return square ~= nil and square:getFloor() ~= nil and not square:isSolid() and not square:isSolidTrans()
end

--- Build a phone from the kit with item id `args.item`, on x, y, z, facing
--- `args.facing`. Returns the point, or nil and a translation key (and what
--- it names).
function Building.build(player, args)
    local x, y, z = tonumber(args and args.x), tonumber(args and args.y), tonumber(args and args.z) or 0
    local facing = args and args.facing
    if not x or not y or not Core.phones.front[facing] then
        return nil, "IGUI_PhunSpawn_CannotBuildHere"
    end
    local why, arg = Building.refusal(player, x, y, z)
    if why then
        return nil, why, arg
    end

    local kit = args.item and player:getInventory():getItemById(args.item)
    if not kit or kit:getFullType() ~= Core.consts.phoneKitItem then
        return nil, "IGUI_PhunSpawn_NoKit"
    end
    if math.abs(math.floor(player:getX()) - x) > REACH or math.abs(math.floor(player:getY()) - y) > REACH or
        math.floor(player:getZ()) ~= z then
        return nil, "IGUI_PhunSpawn_PhoneTooFar"
    end

    -- The phone's own square, and the one in front, where a caller stands
    -- and a traveller lands. Both have to be floor with nothing solid on.
    local square = getCell():getGridSquare(x, y, z)
    local fx, fy = Core.phoneFront(x, y, facing)
    local front = getCell():getGridSquare(fx, fy, z)
    if not standable(square) or not standable(front) then
        return nil, "IGUI_PhunSpawn_CannotBuildHere"
    end
    if Rides.safehouseBlocks(player, fx, fy) then
        return nil, "IGUI_PhunSpawn_NotYourSafehouse"
    end
    local ours, _, vanilla = PhoneSwap.phonesOn(square)
    if ours or vanilla then
        return nil, "IGUI_PhunSpawn_PhoneAlreadyHere"
    end

    local key = Core.accountKey(player)
    local spriteName = Core.phoneSpriteFor(facing, ZombRand)
    if not (spriteName and PhoneSwap.replace(square, nil, spriteName, {
        [Core.consts.phoneOwnerKey] = key
    })) then
        return nil, "IGUI_PhunSpawn_CannotBuildHere"
    end

    -- The kit is spent only now that the phone is up. PhunInteriors' reservoir
    -- kit is spent the same way, from whichever container it is in.
    local container = kit:getContainer()
    player:removeFromHands(kit)
    container:Remove(kit)
    if sendRemoveItemFromContainer then
        sendRemoveItemFromContainer(container, kit)
    end

    local point = PhoneSwap.add(x, y, z, facing, spriteName)
    local record = PhoneSwap.store()[PhoneSwap.keyOf(x, y, z)]
    record.owner = key
    record.built = true
    -- The builder knows their own phone.
    Unlocks.grant(player, point.id)
    Core.logLn(tostring(Core.playerKey(player)) .. " built a pay phone at " .. PhoneSwap.keyOf(x, y, z))
    return point
end

--- Take down a phone this player built, or any built phone for an admin, and
--- give the kit back. A kept phone is refused: an admin released it first,
--- or it would be put back the next time its square loads.
function Building.takeDown(player, args)
    local x, y, z = tonumber(args and args.x), tonumber(args and args.y), tonumber(args and args.z) or 0
    local key = x and y and PhoneSwap.keyOf(x, y, z)
    local record = key and PhoneSwap.store()[key]
    if not record or not record.built then
        return nil, "IGUI_PhunSpawn_NotYourPhone"
    end
    if record.owner ~= Core.accountKey(player) and not Core.tools.isAdmin(player) then
        return nil, "IGUI_PhunSpawn_NotYourPhone"
    end
    if record.kept then
        return nil, "IGUI_PhunSpawn_PhoneIsKept"
    end
    if math.abs(math.floor(player:getX()) - x) > REACH or math.abs(math.floor(player:getY()) - y) > REACH or
        math.floor(player:getZ()) ~= z then
        return nil, "IGUI_PhunSpawn_PhoneTooFar"
    end

    local square = getCell():getGridSquare(x, y, z)
    local ours = square and PhoneSwap.phonesOn(square)
    if ours then
        square:transmitRemoveItemFromSquare(ours)
        square:RecalcProperties()
        square:RecalcAllWithNeighbours(true)
    end
    PhoneSwap.forget(x, y, z)

    local kit = player:getInventory():AddItem(Core.consts.phoneKitItem)
    if kit and sendAddItemToContainer then
        sendAddItemToContainer(player:getInventory(), kit)
    end
    Core.logLn(tostring(Core.playerKey(player)) .. " took down the pay phone at " .. key)
    return true
end

Core.modules.building = Building
return Building
