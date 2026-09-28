if isClient() then
    return
end
require "PhunSpawn/points"
require "PhunSpawn/taxi"
local Core = PhunSpawn
local Unlocks = require "PhunSpawn/unlocks"
local PhoneSwap = require "PhunSpawn/phone_swap"
local Rides = {}

-- ---------------------------------------------------------------------------
-- Rides: fast travel from a known pay phone to another, for a fare.
--
-- Off unless TaxiFastTravel is on. The free ride out of the spawn room is
-- not this; that is the spawn command, and it is free because it is once.
--
-- Every check is made BEFORE anything moves or anybody pays, in the order a
-- player can do something about: stand at a phone, pick one you know, get
-- away from the zombies, then the money. A ride is refused whole or taken
-- whole. The fare is taken only once PhunInteriors has accepted the move, so
-- a refused move costs nothing.
--
-- The fare is PhunMart's "change" pool, read and charged the way PhunMart's
-- own server commands do it, then its client is sent the new wallet. Soft:
-- PhunMart is not a dependency, and without it only a free taxi runs.
-- ---------------------------------------------------------------------------

Rides.POOL = "change"

--- PhunMart's wallet, or nil when PhunMart is not installed.
function Rides.wallet()
    local mart = PhunMart
    return mart and mart.wallet and mart.wallet.getBalance and mart.wallet.adjustByPool and mart.wallet or nil
end

--- The claim over a square that `player` is not welcome in, or nil.
---
--- Asked of the global list rather than of a square, so it answers for a
--- destination nobody has loaded. The rectangle is half open (see
--- PhunInteriors' API table), so one square is x, y to x + 1, y + 1.
--- playerAllowed is member OR owner OR the role capability, which is the
--- question: a member may ride home.
function Rides.safehouseBlocks(player, x, y)
    if not SafeHouse or not SafeHouse.getSafehouseOverlapping then
        return nil
    end
    local claim = SafeHouse.getSafehouseOverlapping(x, y, x + 1, y + 1)
    if not claim then
        return nil
    end
    if claim.playerAllowed and claim:playerAllowed(player) then
        return nil
    end
    return claim
end

--- Is a live zombie within TaxiZombieRadius of the player, on their floor?
function Rides.zombiesNear(player)
    local radius = Core.settings.TaxiZombieRadius or 0
    if radius <= 0 then
        return false
    end
    local cell = getCell()
    local list = cell and cell.getZombieList and cell:getZombieList()
    if not list then
        return false
    end
    local px, py, pz = player:getX(), player:getY(), math.floor(player:getZ())
    local limit = radius * radius
    for i = 0, list:size() - 1 do
        local zombie = list:get(i)
        if zombie and not zombie:isDead() and math.floor(zombie:getZ()) == pz then
            local dx, dy = zombie:getX() - px, zombie:getY() - py
            if (dx * dx) + (dy * dy) <= limit then
                return true
            end
        end
    end
    return false
end

--- Tell the player's client its wallet changed, the way PhunMart's commands
--- do after a charge. In single player the wallet is the same table.
local function syncWallet(player)
    local mart = PhunMart
    if Core.isLocal or not (mart and mart.commands and mart.commands.getWallet) then
        return
    end
    sendServerCommand(player, mart.name, mart.commands.getWallet, {
        username = player:getUsername(),
        wallet = mart.wallet:get(player)
    })
end

--- Take a ride. `args` is {x, y, z} of the phone the player is at, and `id`,
--- the point to go to.
---
--- Returns (point, fare) on success, or (nil, why, arg) with `why` a
--- translation key and `arg` what it names.
function Rides.ride(player, args)
    if not Core.settings.TaxiFastTravel then
        return nil, "IGUI_PhunSpawn_TaxiOff"
    end

    local key, record = PhoneSwap.phoneAt(player, args)
    if not key then
        return nil, record
    end
    local fromId = PhoneSwap.pointId(key)

    local id = args and args.id
    local point = id and Core.points[id]
    if not point or point.discovery ~= Core.discovery.used then
        return nil, "IGUI_PhunSpawn_NoSuchPoint"
    end
    if id == fromId then
        return nil, "IGUI_PhunSpawn_TaxiSamePhone"
    end
    if not Unlocks.has(player, id) then
        return nil, "IGUI_PhunSpawn_NotDiscovered"
    end
    if Rides.zombiesNear(player) then
        return nil, "IGUI_PhunSpawn_TaxiZombies"
    end
    if Rides.safehouseBlocks(player, point.x, point.y) then
        return nil, "IGUI_PhunSpawn_TaxiSafehouse", point.label
    end

    local fx, fy = Core.phoneFront(record.x, record.y, record.facing)
    local fare = Core.taxiFare(fx, fy, point.x, point.y)
    local wallet = fare > 0 and Rides.wallet() or nil
    if fare > 0 then
        if not wallet then
            Core.logLn("a taxi fare needs PhunMart, which is not installed; set both fare options to 0 for a free taxi")
            return nil, "IGUI_PhunSpawn_TaxiNoWallet"
        end
        if wallet:getBalance(player, Rides.POOL) < fare then
            return nil, "IGUI_PhunSpawn_TaxiCantAfford", Core.formatCents(fare)
        end
    end

    if not (PhunInteriors and PhunInteriors.sendTo) then
        Core.logLn("PhunInteriors.sendTo is missing; PhunInteriors is older than this version of PhunSpawn needs")
        return nil, "IGUI_PhunSpawn_CannotGoThere"
    end
    -- Nothing to release: a caller at a phone is out in the world, and one
    -- who holds a room elsewhere keeps it.
    local ok, why = PhunInteriors.sendTo(player, {
        x = point.x,
        y = point.y,
        z = point.z
    }, "phunspawn_taxi", false)
    if not ok then
        Core.logLn("taxi to " .. id .. " refused by PhunInteriors: " .. tostring(why))
        return nil, "IGUI_PhunSpawn_CannotGoThere"
    end

    if fare > 0 then
        wallet:adjustByPool(player, "current", Rides.POOL, -fare)
        syncWallet(player)
    end
    Core.logLn(tostring(Core.playerKey(player)) .. " took a taxi from " .. fromId .. " to " .. id .. " for " ..
                   Core.formatCents(fare))
    return point, fare
end

Core.modules.rides = Rides
return Rides
