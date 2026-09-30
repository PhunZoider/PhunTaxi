-- The taxi and player built phones: finding a phone by walking near it, the
-- fare, a ride and every reason to refuse one, the safehouse rule, and
-- building and taking down a phone.
--
-- Nothing here has a square. What is tested is the order and the outcome of
-- the checks, which is what would fail quietly: a ride that charges and then
-- does not move, one into somebody's safehouse, a build past the limit, or a
-- take down by somebody who did not build it.
local ROOT = os.getenv("PS_ROOT") or "."
local stubs = dofile(ROOT .. "/Tests/lua/stubs.lua")
stubs.install(ROOT)

require "PhunTaxi/core"
require "PhunTaxi/points"
require "PhunTaxi/phones"
require "PhunTaxi/taxi"
local Core = PhunTaxi
Core.logLn = function()
end
Core.debugLn = function()
end

local Unlocks = require "PhunTaxi/unlocks"
local PhoneSwap = require "PhunTaxi/phone_swap"
local Rides = require "PhunTaxi/rides"
local Building = require "PhunTaxi/building"
local Commands = require "PhunTaxi/server_commands"
local report = stubs.reporter()
local check = report.check

local function reset()
    Core.points = {}
    Core.regions = {}
    Core.unlocked = {}
    Core.indexesBuilt = false
    Core.data = {}
    Core.saved = {points = {}, phones = {}, labels = {}, deleted = {}, released = {}}
    Core.settings.PhoneChance = 50
    Core.settings.PhoneDistance = 500
    Core.settings.DiscoveryRadius = 12
    Core.settings.PhoneDiscoverRadius = 0
    Core.settings.TaxiFastTravel = true
    Core.settings.TaxiCentsPerSquare = 1
    Core.settings.TaxiMinimumFare = 100
    Core.settings.TaxiZombieRadius = 6
    Core.settings.AllowBuiltPoints = true
    Core.settings.BuiltPointLimit = 5
    Core.settings.BuiltPhoneDistance = 50
    PhunZones = nil
    SafeHouse = nil
end

-- A player with an inventory: enough for a kit to be found, spent and given
-- back.
local function playerWithKit(name, kits)
    local p = stubs.player(name, 5)
    local items = {}
    local nextId = 100
    local inventory = {}
    local function add(fullType)
        nextId = nextId + 1
        local item = {id = nextId}
        item.getID = function() return item.id end
        item.getFullType = function() return fullType end
        item.getContainer = function() return inventory end
        items[item.id] = item
        return item
    end
    inventory.getItemById = function(_, id) return items[id] end
    inventory.Remove = function(_, item) items[item.id] = nil end
    inventory.AddItem = function(_, fullType) return add(fullType) end
    inventory.count = function()
        local n = 0
        for _ in pairs(items) do n = n + 1 end
        return n
    end
    p.getInventory = function() return inventory end
    p.removeFromHands = function() end
    p.kits = {}
    for _ = 1, kits or 0 do
        table.insert(p.kits, add(Core.consts.phoneKitItem))
    end
    return p
end

-- ---------------------------------------------------------------------------
-- Taxi tiles, the fare and money.
-- ---------------------------------------------------------------------------
reset()
check("_0 is a taxi tile", Core.isTaxiTile("phuninteriors_02_0"), true)
check("_39 is", Core.isTaxiTile("phuninteriors_02_39"), true)
check("_40 is not", Core.isTaxiTile("phuninteriors_02_40"), false)
check("another sheet is not", Core.isTaxiTile("phuninteriors_01_0"), false)
check("nil is not", Core.isTaxiTile(nil), false)

check("a short ride costs the minimum", Core.taxiFare(0, 0, 30, 40), 100)
check("a long one costs per square", Core.taxiFare(0, 0, 300, 400), 500)
check("rounded up", Core.taxiFare(0, 0, 0, 100.2), 101)
Core.settings.TaxiCentsPerSquare, Core.settings.TaxiMinimumFare = 0, 0
check("both zero is free", Core.taxiFare(0, 0, 3000, 4000), 0)
check("money reads as dollars", Core.formatCents(1234), "$12.34")
check("and pads cents", Core.formatCents(5), "$0.05")

-- ---------------------------------------------------------------------------
-- Finding a phone by walking near it.
-- ---------------------------------------------------------------------------
reset()
PhoneSwap.add(1000, 2000, 0, "S", "phuninteriors_01_17")
local phoneId = "phun.spawn.phone.1000_2000_0"
local walker = stubs.player("walker", 5)
walker.moveTo(1000, 2002, 0)
check("at 0, walking up finds nothing", Unlocks.checkDiscovery(walker), nil)
check("and the phone is not known", Unlocks.has(walker, phoneId), false)

Core.settings.PhoneDiscoverRadius = 3
walker.moveTo(1000, 2006, 0)
check("at 3, but too far, finds nothing", Unlocks.checkDiscovery(walker), nil)
walker.moveTo(1000, 2003, 0)
local found = Unlocks.checkDiscovery(walker)
check("at 3 and near finds the phone", found and found.id, phoneId)
check("and it is known", Unlocks.has(walker, phoneId), true)

local told = PhoneSwap.announcement(found)
check("the news carries the phone's square to ring", told.phone and told.phone.y, 2000)
check("and says it was a phone", told.text, "IGUI_PhunTaxi_PhoneFound")
Core.registerPoint("a.place", {label = "Place", x = 5, y = 5})
check("a place carries no square", PhoneSwap.announcement(Core.points["a.place"]).phone, nil)

local payloadPhone
for _, row in ipairs(Unlocks.payloadFor(walker)) do
    if row.id == phoneId then
        payloadPhone = row
    end
end
check("the payload marks a phone by its square", payloadPhone and payloadPhone.phone, "1000_2000_0")

-- ---------------------------------------------------------------------------
-- A ride.
-- ---------------------------------------------------------------------------
local sends
local sendOk = true
PhunInteriors = {
    sendTo = function(player, destination, reason, release)
        table.insert(sends, {destination = destination, reason = reason, release = release})
        return sendOk, sendOk and 0 or "no"
    end
}
local balances = {}
PhunMart = {
    wallet = {
        getBalance = function(_, player, pool)
            return balances[player:getUsername()] or 0
        end,
        adjustByPool = function(_, player, kind, pool, amount)
            balances[player:getUsername()] = (balances[player:getUsername()] or 0) + amount
        end
    }
}

local function setupRide()
    reset()
    sends = {}
    sendOk = true
    PhoneSwap.add(1000, 2000, 0, "S", "phuninteriors_01_17") -- in front: 1000, 2001
    PhoneSwap.add(1000, 2600, 0, "S", "phuninteriors_01_17") -- in front: 1000, 2601
    local rider = stubs.player("rider", 5)
    rider.moveTo(1000, 2001, 0)
    Unlocks.grant(rider, "phun.spawn.phone.1000_2000_0")
    Unlocks.grant(rider, "phun.spawn.phone.1000_2600_0")
    balances.rider = 1000
    return rider
end
local from = {x = 1000, y = 2000, z = 0}
local function to(id)
    return {x = from.x, y = from.y, z = from.z, id = id}
end
local there = "phun.spawn.phone.1000_2600_0"

local rider = setupRide()
local point, fare = Rides.ride(rider, to(there))
check("a ride goes", point and point.id, there)
check("600 squares at a cent is $6", fare, 600)
check("and is charged", balances.rider, 400)
check("through PhunInteriors", #sends, 1)
check("to the square in front of the phone", sends[1] and sends[1].destination.y, 2601)
check("releasing nothing", sends[1] and sends[1].release, false)

rider = setupRide()
Core.settings.TaxiFastTravel = false
local _, why = Rides.ride(rider, to(there))
check("off, there is no taxi", why, "IGUI_PhunTaxi_TaxiOff")

rider = setupRide()
rider.moveTo(1100, 2100, 0)
_, why = Rides.ride(rider, to(there))
check("away from the phone, no taxi", why, "IGUI_PhunTaxi_PhoneTooFar")

rider = setupRide()
_, why = Rides.ride(rider, {x = 1500, y = 1500, z = 0, id = there})
check("from somewhere that is not a phone, no taxi", why, "IGUI_PhunTaxi_PhoneTooFar")

rider = setupRide()
_, why = Rides.ride(rider, to("phun.spawn.phone.1000_2000_0"))
check("to the same phone, no", why, "IGUI_PhunTaxi_TaxiSamePhone")
Core.registerPoint("a.place", {label = "Place", x = 5, y = 5, discovery = Core.discovery.start})
_, why = Rides.ride(rider, to("a.place"))
check("to a place that is not a phone, no", why, "IGUI_PhunTaxi_NoSuchPoint")

-- A place registered with a phone is somewhere a taxi goes, and a start
-- point is known without anybody using its phone.
rider = setupRide()
Core.registerPoint("a.diner", {label = "Diner", x = 1001, y = 2300, discovery = Core.discovery.start, phone = "E"})
point = Rides.ride(rider, to("a.diner"))
check("to a place with a phone, yes", point and point.id, "a.diner")
check("arriving in front of its phone", sends[1] and sends[1].destination.x, 1001)

-- And a ride starts from its phone too.
rider = setupRide()
Core.registerPoint("a.diner", {label = "Diner", x = 1001, y = 2300, discovery = Core.discovery.start, phone = "E"})
rider.moveTo(1001, 2300, 0)
_, why = Rides.ride(rider, {x = 1000, y = 2300, z = 0, id = "a.diner"})
check("from a place's phone to itself, no", why, "IGUI_PhunTaxi_TaxiSamePhone")
point = Rides.ride(rider, {x = 1000, y = 2300, z = 0, id = there})
check("from a place's phone to a pay phone, yes", point and point.id, there)

rider = setupRide()
Unlocks.revoke(rider, "phun.spawn.phone.1000_2000_0")
_, why = Rides.ride(rider, to(there))
check("from a phone not known, no", why, "IGUI_PhunTaxi_TaxiPhoneUnknown")
check("and nobody moves", #sends, 0)

rider = setupRide()
Unlocks.revoke(rider, there)
_, why = Rides.ride(rider, to(there))
check("to a phone not known, no", why, "IGUI_PhunTaxi_NotDiscovered")

rider = setupRide()
balances.rider = 599
local arg
_, why, arg = Rides.ride(rider, to(there))
check("short of the fare, no", why, "IGUI_PhunTaxi_TaxiCantAfford")
check("saying how much", arg, "$6.00")
check("and nothing is taken", balances.rider, 599)
check("and nobody moves", #sends, 0)

rider = setupRide()
sendOk = false
_, why = Rides.ride(rider, to(there))
check("a move PhunInteriors refuses is refused", why, "IGUI_PhunTaxi_CannotGoThere")
check("and costs nothing", balances.rider, 1000)

rider = setupRide()
local mart = PhunMart
PhunMart = nil
_, why = Rides.ride(rider, to(there))
check("a fare with no PhunMart is refused", why, "IGUI_PhunTaxi_TaxiNoWallet")
Core.settings.TaxiCentsPerSquare, Core.settings.TaxiMinimumFare = 0, 0
point = Rides.ride(rider, to(there))
check("a free taxi runs without PhunMart", point ~= nil, true)
PhunMart = mart

-- Zombies.
rider = setupRide()
local realGetCell = getCell
local zombieAt = {x = 1003, y = 2001, z = 0}
getCell = function()
    return {
        getGridSquare = function() return nil end,
        getZombieList = function()
            return {
                size = function() return 1 end,
                get = function()
                    return {
                        isDead = function() return false end,
                        getX = function() return zombieAt.x end,
                        getY = function() return zombieAt.y end,
                        getZ = function() return zombieAt.z end
                    }
                end
            }
        end
    }
end
_, why = Rides.ride(rider, to(there))
check("a zombie close by, no taxi", why, "IGUI_PhunTaxi_TaxiZombies")
zombieAt.x = 1020
check("one further off does not stop it", Rides.ride(rider, to(there)) ~= nil, true)
zombieAt.x, zombieAt.z = 1003, 1
rider = setupRide()
check("nor one on another floor", Rides.ride(rider, to(there)) ~= nil, true)
getCell = realGetCell

-- Safehouses: someone else's is refused, your own is not.
local members = {}
local function claimAround(x1, y1, x2, y2)
    SafeHouse = {
        getSafehouseOverlapping = function(ax, ay, bx, by)
            if ax < x2 and bx > x1 and ay < y2 and by > y1 then
                return {
                    playerAllowed = function(_, player) return members[player:getUsername()] == true end
                }
            end
            return nil
        end
    }
end
rider = setupRide()
claimAround(990, 2590, 1010, 2610)
_, why = Rides.ride(rider, to(there))
check("into somebody's safehouse, no", why, "IGUI_PhunTaxi_TaxiSafehouse")
check("and nothing is taken", balances.rider, 1000)
claimAround(990, 2590, 1010, 2610)
members.rider = true
check("into your own, yes", Rides.ride(rider, to(there)) ~= nil, true)
members.rider = nil

-- The first ride is never into somebody's safehouse either, and a refusal
-- keeps the choice.
reset()
Core.isLocal = false
local sent = {}
Core.respond = function(player, command, args)
    table.insert(sent, {command = command, args = args})
end
sends = {}
Core.registerPoint("a.home", {label = "Home", x = 5000, y = 5000, discovery = Core.discovery.start})
claimAround(4990, 4990, 5010, 5010)
local newbie = stubs.player("newbie", 0)
Commands[Core.commands.spawn](newbie, {id = "a.home"})
check("a first ride into a safehouse is refused", #sends, 0)
check("saying why", sent[#sent].args.text, "IGUI_PhunTaxi_TaxiSafehouse")
local Placement = require "PhunTaxi/placement"
check("and the choice is still open", Placement.canSpawn(newbie), true)
SafeHouse = nil
Commands[Core.commands.spawn](newbie, {id = "a.home"})
check("without the claim it goes", #sends, 1)
Core.isLocal = true

-- ---------------------------------------------------------------------------
-- Building.
-- ---------------------------------------------------------------------------
reset()
local builder = playerWithKit("builder", 1)
local key = Core.accountKey(builder)
check("an open square is allowed so far", Building.refusal(builder, 100, 100, 0), nil)
Core.settings.AllowBuiltPoints = false
check("off, nobody builds", Building.refusal(builder, 100, 100, 0), "IGUI_PhunTaxi_BuiltPointsOff")
Core.settings.AllowBuiltPoints = true

PhoneSwap.add(130, 100, 0, "S", "phuninteriors_01_17")
local tooClose, apart = Building.refusal(builder, 100, 100, 0)
check("within 50 of any phone, no", tooClose, "IGUI_PhunTaxi_PhoneTooClose")
check("saying how far", apart, "50")
check("50 away is fine", Building.refusal(builder, 80, 100, 0), nil)

for i = 1, 5 do
    PhoneSwap.add(1000 * i, 9000, 0, "S", "phuninteriors_01_17")
    PhoneSwap.store()[i * 1000 .. "_9000_0"].owner = key
end
check("five standing is the count", Building.count(key), 5)
local limited, limit = Building.refusal(builder, 20000, 20000, 0)
check("at the limit, no", limited, "IGUI_PhunTaxi_BuiltPointLimit")
check("saying the limit", limit, "5")
Core.settings.BuiltPointLimit = 0
check("zero is no limit", Building.refusal(builder, 20000, 20000, 0), nil)
Core.settings.BuiltPointLimit = 5

claimAround(19990, 19990, 20010, 20010)
PhoneSwap.store()["5000_9000_0"] = nil
check("in somebody's safehouse, no", Building.refusal(builder, 20000, 20000, 0), "IGUI_PhunTaxi_NotYourSafehouse")
members.builder = true
check("in your own, yes", Building.refusal(builder, 20000, 20000, 0), nil)
members.builder = nil
SafeHouse = nil

builder.moveTo(20000, 20001, 0)
_, why = Building.build(builder, {x = 20000, y = 20000, z = 0, facing = "S", item = 99999})
check("without the kit, no", why, "IGUI_PhunTaxi_NoKit")
_, why = Building.build(builder, {x = 20000, y = 20000, z = 0, facing = "up", item = builder.kits[1]:getID()})
check("a bad facing, no", why, "IGUI_PhunTaxi_CannotBuildHere")
_, why = Building.build(builder, {x = 20000, y = 20000, z = 0, facing = "S", item = builder.kits[1]:getID()})
check("no square to build on, no", why, "IGUI_PhunTaxi_CannotBuildHere")
check("and the kit is kept", builder:getInventory():count(), 1)

-- ---------------------------------------------------------------------------
-- Taking one down.
-- ---------------------------------------------------------------------------
reset()
local owner = playerWithKit("owner", 0)
local stranger = playerWithKit("stranger", 0)
PhoneSwap.add(300, 300, 0, "S", "phuninteriors_01_17")
local record = PhoneSwap.store()["300_300_0"]
owner.moveTo(300, 301, 0)
stranger.moveTo(300, 301, 0)

_, why = Building.takeDown(owner, {x = 300, y = 300, z = 0})
check("a swapped phone is nobody's to take down", why, "IGUI_PhunTaxi_NotYourPhone")
record.built, record.owner = true, Core.accountKey(owner)
Core.isLocal = false
_, why = Building.takeDown(stranger, {x = 300, y = 300, z = 0})
check("a stranger cannot", why, "IGUI_PhunTaxi_NotYourPhone")
Core.isLocal = true
record.kept = true
_, why = Building.takeDown(owner, {x = 300, y = 300, z = 0})
check("a kept one cannot be", why, "IGUI_PhunTaxi_PhoneIsKept")
record.kept = nil
check("the builder can", Building.takeDown(owner, {x = 300, y = 300, z = 0}), true)
check("it is forgotten", PhoneSwap.store()["300_300_0"], nil)
check("and so is its point", Core.points["phun.spawn.phone.300_300_0"], nil)
check("and the kit comes back", owner:getInventory():count(), 1)

os.exit(report.finish("taxi") > 0 and 1 or 0)
