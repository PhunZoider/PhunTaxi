-- Pay phones: the swap table, the spacing, and a swapped phone as a point.
--
-- The swap itself replaces an object on a square and is tested in game or not
-- at all. What is here is everything around it that fails silently: a target
-- that maps to no replacement, spacing that lets two phones share a street,
-- a phone that registers nowhere, and a phone that hides an explore point
-- from the discovery sweep.
local ROOT = os.getenv("PS_ROOT") or "."
local stubs = dofile(ROOT .. "/Tests/lua/stubs.lua")
stubs.install(ROOT)

require "PhunTaxi/core"
require "PhunTaxi/points"
require "PhunTaxi/phones"
local Core = PhunTaxi
Core.logLn = function()
end
Core.debugLn = function()
end

local Unlocks = require "PhunTaxi/unlocks"
local PhoneSwap = require "PhunTaxi/phone_swap"
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
    Core.settings.ShowUndiscovered = false
    PhunZones = nil
end

-- ---------------------------------------------------------------------------
-- The shipped table: four vanilla phones, four of ours, facings matching.
-- ---------------------------------------------------------------------------
check("_38 faces east", Core.phoneTargetFacing("street_decoration_01_38"), "E")
check("_39 faces south", Core.phoneTargetFacing("street_decoration_01_39"), "S")
check("_46 faces west", Core.phoneTargetFacing("street_decoration_01_46"), "W")
check("_47 faces north", Core.phoneTargetFacing("street_decoration_01_47"), "N")
check("east becomes _16", Core.phoneSpriteFor("E"), "phuninteriors_01_16")
check("south becomes _17", Core.phoneSpriteFor("S"), "phuninteriors_01_17")
check("west becomes _18", Core.phoneSpriteFor("W"), "phuninteriors_01_18")
check("north becomes _19", Core.phoneSpriteFor("N"), "phuninteriors_01_19")
check("_16 is one of ours", Core.phoneFacing("phuninteriors_01_16"), "E")
check("_19 is one of ours", Core.phoneFacing("phuninteriors_01_19"), "N")
check("a vanilla phone is not ours", Core.phoneFacing("street_decoration_01_38"), nil)
check("one of ours is not a target", Core.phoneTargetFacing("phuninteriors_01_16"), nil)
check("nil is neither", Core.phoneFacing(nil), nil)

-- Every target has somewhere to go. A target whose facing has no replacement
-- would be stamped, lose its roll to nothing, and never roll again.
for sprite, facing in pairs(Core.phones.targets) do
    check(sprite .. " has a replacement", Core.phoneSpriteFor(facing) ~= nil, true)
end

-- ---------------------------------------------------------------------------
-- Adding to the table.
-- ---------------------------------------------------------------------------
check("a bad facing is refused", Core.addPhoneTarget("some_tile_0", "up"), false)
check("and not stored", Core.phones.targets["some_tile_0"], nil)
check("a new target is taken", Core.addPhoneTarget("some_tile_0", "S"), true)
check("and faces the way it said", Core.phoneTargetFacing("some_tile_0"), "S")

check("a second replacement is taken", Core.addPhoneSprite("S", "other_phones_01_1"), true)
check("south is now a list", type(Core.phones.sprites.S), "table")
check("the first is kept", Core.phoneSpriteFor("S", function()
    return 0
end), "phuninteriors_01_17")
check("the second is picked", Core.phoneSpriteFor("S", function()
    return 1
end), "other_phones_01_1")
check("the new one is recognised", Core.phoneFacing("other_phones_01_1"), "S")
check("and so is the old one", Core.phoneFacing("phuninteriors_01_17"), "S")

check("replace takes over", Core.addPhoneSprite("S", "phuninteriors_01_17", true), true)
check("south is one sprite again", Core.phones.sprites.S, "phuninteriors_01_17")
check("the dropped one is not ours now", Core.phoneFacing("other_phones_01_1"), nil)
Core.phones.targets["some_tile_0"] = nil

-- ---------------------------------------------------------------------------
-- Where a character stands, and so wakes up: in front, never on the phone.
-- ---------------------------------------------------------------------------
local fx, fy = Core.phoneFront(100, 200, "E")
check("east: in front is x+1", fx .. "," .. fy, "101,200")
fx, fy = Core.phoneFront(100, 200, "S")
check("south: in front is y+1", fx .. "," .. fy, "100,201")
fx, fy = Core.phoneFront(100, 200, "W")
check("west: in front is x-1", fx .. "," .. fy, "99,200")
fx, fy = Core.phoneFront(100, 200, "N")
check("north: in front is y-1", fx .. "," .. fy, "100,199")

-- ---------------------------------------------------------------------------
-- Spacing.
-- ---------------------------------------------------------------------------
reset()
check("an empty map is far enough", PhoneSwap.farEnough(1000, 1000), true)
PhoneSwap.add(1000, 1000, 0, "S", "phuninteriors_01_17")
check("right beside it is not", PhoneSwap.farEnough(1001, 1000), false)
check("499 away is not", PhoneSwap.farEnough(1499, 1000), false)
check("500 away is", PhoneSwap.farEnough(1500, 1000), true)
-- Euclidean, not a box: 400 across and 400 down is 566 away.
check("a diagonal is measured straight", PhoneSwap.farEnough(1400, 1400), true)
Core.settings.PhoneDistance = 0
check("zero turns spacing off", PhoneSwap.farEnough(1001, 1000), true)

-- ---------------------------------------------------------------------------
-- A PhunZones zone's own chance and spacing. Squares with x below 5000 are in
-- "town", which sets both; the rest are in a zone that sets neither.
-- ---------------------------------------------------------------------------
reset()
local town = {title = "Muldraugh"}
PhunZones = {
    inied = true,
    getLocation = function(x)
        return x < 5000 and town or {title = "Woods"}
    end
}
check("no zone value is the sandbox chance", PhoneSwap.chanceAt(6000, 0), 50)
check("no zone value is the sandbox spacing", PhoneSwap.spacingAt(6000, 0), 500)
town.phoneChance = 90
town.phoneDistance = 100
check("the zone's chance", PhoneSwap.chanceAt(1000, 0), 90)
check("the zone's spacing", PhoneSwap.spacingAt(1000, 0), 100)
town.phoneChance, town.phoneDistance = 0, 0
check("a zone's zero is a value, not unset", PhoneSwap.chanceAt(1000, 0), 0)
check("and so is a zero spacing", PhoneSwap.spacingAt(1000, 0), 0)
town.phoneChance, town.phoneDistance = 250, -5
check("chance is clamped to 100", PhoneSwap.chanceAt(1000, 0), 100)
check("spacing is clamped to 0", PhoneSwap.spacingAt(1000, 0), 0)
town.phoneChance, town.phoneDistance = "", "abc"
check("text is unset", PhoneSwap.chanceAt(1000, 0), 50)
check("and so is bad text", PhoneSwap.spacingAt(1000, 0), 500)
PhunZones.getLocation = function()
    error("not ready")
end
check("a PhunZones error is the sandbox value", PhoneSwap.chanceAt(1000, 0), 50)

-- The spacing is the zone of the phone being placed.
PhunZones.getLocation = function(x)
    return x < 5000 and town or {title = "Woods"}
end
town.phoneDistance = 100
PhoneSwap.add(4900, 1000, 0, "S")
check("in town 150 away is far enough", PhoneSwap.farEnough(4750, 1000), true)
check("in the woods 150 away is not", PhoneSwap.farEnough(5050, 1000), false)
check("a built phone's own spacing ignores the zone", PhoneSwap.farEnough(4750, 1000, 500), false)

-- A map phone's chance is the zone's, or the sandbox's. The last two digits
-- of a square's rank are its chance roll, so a rank of 60 rolls 60: it wins
-- at a chance of 70 and loses at 50. Far apart, so spacing stays out of it.
Core.phones.candidates = {}
Core.data.phoneRanks = {
    ["1000_3000_0"] = 60,
    ["6000_3000_0"] = 160,
    ["2000_9000_0"] = 260
}
town.phoneChance = 70
Core.addMapPhone(1000, 3000, 0, "S")
Core.addMapPhone(6000, 3000, 0, "S")
PhoneSwap.relocate()
PhoneSwap.resolve()
check("a town phone is taken at the zone's 70", PhoneSwap.store()["1000_3000_0"] ~= nil, true)
check("pending until its square loads", PhoneSwap.store()["1000_3000_0"].pending, true)
check("and in its zone at once, not Elsewhere", PhoneSwap.store()["1000_3000_0"].region, town.title)
check("so its point is too", Core.points["phun.spawn.phone.1000_3000_0"].region, town.title)
check("a woods phone is not, at the sandbox 50", PhoneSwap.store()["6000_3000_0"], nil)
town.phoneChance = 0
Core.addMapPhone(2000, 9000, 0, "S")
PhoneSwap.relocate()
PhoneSwap.resolve()
check("a zone at zero takes nothing", PhoneSwap.store()["2000_9000_0"], nil)
check("and lets go of one it had taken", PhoneSwap.store()["1000_3000_0"], nil)
-- The sandbox off does not stop a zone that turns it on.
Core.settings.PhoneChance = 0
town.phoneChance = 100
PhoneSwap.relocate()
PhoneSwap.resolve()
check("a zone turns the pool on over a sandbox zero", PhoneSwap.store()["2000_9000_0"] ~= nil, true)
check("and the woods stay off", PhoneSwap.store()["6000_3000_0"], nil)

-- PhunZones installed and not set up yet: never asked, because asking sets
-- it up early, and the pool waits for it.
local asked = false
PhunZones.inied = false
PhunZones.getLocation = function()
    asked = true
    return town
end
check("not ready is the sandbox chance", PhoneSwap.chanceAt(1000, 0), 0)
Core.addMapPhone(3000, 9000, 0, "S")
PhoneSwap.ready = true
PhoneSwap.loadGridsquare({
    getX = function() return 1 end,
    getY = function() return 1 end,
    getZ = function() return 0 end
})
check("not ready takes nothing", PhoneSwap.store()["3000_9000_0"], nil)
check("and never asks PhunZones", asked, false)
PhoneSwap.ready = false
PhunZones.inied = true
Core.phones.candidates = {}
Core.phones.candidatesVersion = Core.phones.candidatesVersion + 1

-- ---------------------------------------------------------------------------
-- A swapped phone is a point, in front of the phone, found by using it.
-- ---------------------------------------------------------------------------
reset()
PhunZones = {
    inied = true,
    getLocation = function()
        return {
            title = "Muldraugh",
            subtitle = "Downtown"
        }
    end
}
local point = PhoneSwap.add(1000, 2000, 0, "W", "phuninteriors_01_18")
check("add registers a point", point ~= nil, true)
check("under the phone's id", point and point.id, "phun.spawn.phone.1000_2000_0")
check("in front of the phone", point and (point.x .. "," .. point.y), "999,2000")
check("discovered by use", point and point.discovery, "used")
check("region from PhunZones", point and point.region, "Muldraugh")
check("label names the place", point and point.label, "Downtown pay phone")
check("and it is recorded", PhoneSwap.store()["1000_2000_0"] ~= nil, true)

-- A restart: the registry is empty, the record is not.
Core.points = {}
Core.indexesBuilt = false
PhoneSwap.start()
check("start registers recorded phones", Core.points["phun.spawn.phone.1000_2000_0"] ~= nil, true)

-- Without PhunZones there is still a point, in no region.
PhunZones = nil
point = PhoneSwap.add(5000, 5000, 0, "N", "phuninteriors_01_19")
check("no PhunZones still registers", point ~= nil, true)
check("with no region", point and point.region, nil)
check("and a plain label", point and point.label, "Pay phone")

-- A map phone is named after the building phones.pl found it in.
check("a map phone takes a room", Core.addMapPhone(5100, 5000, 0, "N", nil, "gasstore"), true)
check("the room is on the candidate", Core.phones.candidates["5100_5000_0"].room, "gasstore")
check("an empty room is none", Core.addMapPhone(5200, 5000, 0, "N", nil, "") and
    Core.phones.candidates["5200_5000_0"].room, nil)
check("it names the phone", PhoneSwap.labelFor({}, "5100_5000_0"), "Gas station")
check("after the subtitle", PhoneSwap.labelFor({subtitle = "Downtown"}, "5100_5000_0"), "Downtown Gas station")
Core.addMapPhone(5300, 5000, 0, "N", nil, "lostandfound")
check("a room with no word is not guessed at", PhoneSwap.labelFor({}, "5300_5000_0"), "Pay phone")
point = PhoneSwap.add(5100, 5000, 0, "N", "phuninteriors_01_19")
check("and the point carries it", point and point.label, "Gas station")
PhoneSwap.forget(5100, 5000, 0)
for _, key in ipairs({"5100_5000_0", "5200_5000_0", "5300_5000_0"}) do
    Core.phones.candidates[key] = nil
end

check("forget removes the record", PhoneSwap.forget(5000, 5000, 0), true)
check("and the point", Core.points["phun.spawn.phone.5000_5000_0"], nil)
check("forgetting twice is nothing", PhoneSwap.forget(5000, 5000, 0), false)

-- ---------------------------------------------------------------------------
-- Using one. The world here is empty, so the square check is skipped and the
-- record is the whole answer; the square check is tested in game.
-- ---------------------------------------------------------------------------
reset()
PhoneSwap.add(1000, 2000, 0, "S", "phuninteriors_01_17")
local bob = stubs.player("bob", 5)

bob.moveTo(1100, 2000, 0)
local got, why = PhoneSwap.use(bob, {x = 1000, y = 2000, z = 0})
check("too far is refused", got, nil)
check("and says so", why, "IGUI_PhunTaxi_PhoneTooFar")

bob.moveTo(1000, 2001, 0)
got, why = PhoneSwap.use(bob, {x = 1000, y = 2000, z = 1})
check("another level is too far", why, "IGUI_PhunTaxi_PhoneTooFar")

bob.moveTo(1030, 2001, 0)
got, why = PhoneSwap.use(bob, {x = 1030, y = 2000, z = 0})
check("an unrecorded phone is dead", why, "IGUI_PhunTaxi_PhoneDead")

bob.moveTo(1000.6, 2001.4, 0)
got, why = PhoneSwap.use(bob, {x = 1000, y = 2000, z = 0})
check("standing at it works", got and got.id, "phun.spawn.phone.1000_2000_0")
check("and grants it", why, true)
check("bob knows it now", Unlocks.has(bob, "phun.spawn.phone.1000_2000_0"), true)
got, why = PhoneSwap.use(bob, {x = 1000, y = 2000, z = 0})
check("a second use still answers", got ~= nil, true)
check("with nothing new", why, false)

got, why = PhoneSwap.use(bob, {})
check("no square is dead", why, "IGUI_PhunTaxi_PhoneDead")

-- A phone of ours standing with no record, one an admin put down from the
-- item: recorded on use, and on its square loading.
local function squareWith(x, y, z, spriteName)
    local objects = {{
        getSprite = function()
            return {getName = function() return spriteName end}
        end,
        getModData = function() return {} end
    }}
    return {
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return z end,
        getObjects = function()
            return {
                size = function() return #objects end,
                get = function(_, i) return objects[i + 1] end
            }
        end
    }
end
local realGetCell = getCell
local placed = {
    ["1060_2000_0"] = squareWith(1060, 2000, 0, "phuninteriors_01_17"),
    ["1090_2000_0"] = squareWith(1090, 2000, 0, "phuninteriors_01_18")
}
getCell = function()
    return {getGridSquare = function(_, x, y, z) return placed[x .. "_" .. y .. "_" .. z] end}
end

bob.moveTo(1060, 2001, 0)
got, why = PhoneSwap.use(bob, {x = 1060, y = 2000, z = 0})
check("a placed phone is recorded on use", got and got.id, "phun.spawn.phone.1060_2000_0")
check("and granted", why, true)
check("and kept its facing", PhoneSwap.store()["1060_2000_0"].facing, "S")
check("but not kept", PhoneSwap.store()["1060_2000_0"].kept, nil)

-- Only on a square something names: the pool, or a record. Every other
-- square is ruled out without a look at what stands on it.
PhoneSwap.ready = true
PhoneSwap.loadGridsquare(placed["1090_2000_0"])
check("a square nothing names is not looked at", PhoneSwap.store()["1090_2000_0"], nil)
Core.data.phoneRanks = {["1090_2000_0"] = 99}
Core.addMapPhone(1090, 2000, 0, "W")
PhoneSwap.loadGridsquare(placed["1090_2000_0"])
check("one of ours on a pool square is recorded on load", Core.points["phun.spawn.phone.1090_2000_0"] ~= nil,
    true)
check("facing west", PhoneSwap.store()["1090_2000_0"].facing, "W")
check("and standing, not pending", PhoneSwap.store()["1090_2000_0"].pending, nil)
PhoneSwap.ready = false
Core.phones.candidates = {}
Core.phones.candidatesVersion = Core.phones.candidatesVersion + 1
getCell = realGetCell
bob.moveTo(1000, 2001, 0)

-- The location is looked at again on use, for a phone that swapped before
-- PhunZones was ready.
PhunZones = {
    inied = true,
    getLocation = function()
        return {
            title = "West Point"
        }
    end
}
PhoneSwap.use(bob, {x = 1000, y = 2000, z = 0})
check("use refreshes the region", Core.points["phun.spawn.phone.1000_2000_0"].region, "West Point")

-- And once for every record, on the first square load after PhunZones is
-- set up, so a phone adopted at boot does not wait to be used.
local bare = {
    getX = function() return 1 end,
    getY = function() return 1 end,
    getZ = function() return 0 end,
    getObjects = function() return {size = function() return 0 end} end
}
PhoneSwap.store()["1000_2000_0"].region = nil
PhoneSwap.located = false
PhunZones.inied = false
PhoneSwap.ready = true
PhoneSwap.loadGridsquare(bare)
check("not relocated before PhunZones is ready", PhoneSwap.store()["1000_2000_0"].region, nil)
PhunZones.inied = true
PhoneSwap.loadGridsquare(bare)
check("relocated on the first load after", Core.points["phun.spawn.phone.1000_2000_0"].region, "West Point")
PhoneSwap.ready = false

-- ---------------------------------------------------------------------------
-- A phone never hides an explore point from the sweep, and is never found by
-- walking past.
-- ---------------------------------------------------------------------------
reset()
Core.registerPoint("a.explore", {label = "Explore", x = 1010, y = 2000, z = 0})
PhoneSwap.add(1000, 2000, 0, "S", "phuninteriors_01_17")
local amy = stubs.player("amy", 5)
amy.moveTo(1000, 2003, 0)
local found = Unlocks.checkDiscovery(amy)
check("the explore point is found past the phone", found and found.id, "a.explore")
check("the phone is not found by walking", Unlocks.has(amy, "phun.spawn.phone.1000_2000_0"), false)

-- ---------------------------------------------------------------------------
-- An unused phone stays out of the payload even with ShowUndiscovered on.
-- ---------------------------------------------------------------------------
Core.settings.ShowUndiscovered = true
local sawPhone, sawOther = false, false
for _, p in ipairs(Unlocks.payloadFor(stubs.player("cat", 5))) do
    if p.id == "phun.spawn.phone.1000_2000_0" then
        sawPhone = true
    elseif p.id == "a.explore" then
        sawOther = true
    end
end
check("an undiscovered place is listed", sawOther, true)
check("an unused phone is not", sawPhone, false)

-- ---------------------------------------------------------------------------
-- Ringing is decided client side, from the squares the client has loaded and
-- the phone keys in its points payload. So the key the payload carries for a
-- phone and the key the client builds from its square must be the same string.
-- ---------------------------------------------------------------------------
reset()
local registered = PhoneSwap.add(1000, 2000, 0, "S", "phuninteriors_01_17")
check("client and server agree on a phone's id", Core.phonePointId(1000, 2000, 0), registered.id)
check("and on its square", Core.phoneKey(1000, 2000, 0), registered.phoneKey)
local sam = stubs.player("sam", 5)
Unlocks.grant(sam, registered.id)
local carried
for _, p in ipairs(Unlocks.payloadFor(sam)) do
    if p.id == registered.id then
        carried = p.phone
    end
end
check("a known phone carries its square in the payload", carried, Core.phoneKey(1000, 2000, 0))

local function spotsOf()
    return {
        a = {x = 1000, y = 2000, z = 0},
        b = {x = 1010, y = 2000, z = 0},
        c = {x = 1015, y = 2000, z = 0},
        gone = {x = 1001, y = 2000, z = 0}
    }
end
-- a, b are ours; c is still vanilla (its swap has not reached us); gone has
-- unloaded.
local stands = {a = true, b = true, c = false}
local function standingOf(spot)
    for key, value in pairs(spotsOf()) do
        if value.x == spot.x then
            return stands[key]
        end
    end
end

local spots = spotsOf()
local rings = Core.phoneToRing(spots, {}, 1003, 2000, 20, standingOf)
check("the nearest of ours rings", rings and rings.x, 1000)
check("an unloaded square is forgotten", spots.gone, nil)
check("a vanilla one is kept for later", spots.c ~= nil, true)

rings = Core.phoneToRing(spotsOf(), {[Core.phoneKey(1000, 2000, 0)] = true}, 1003, 2000, 20, standingOf)
check("a known phone does not, the next does", rings and rings.x, 1010)

rings = Core.phoneToRing(spotsOf(), {
    [Core.phoneKey(1000, 2000, 0)] = true,
    [Core.phoneKey(1010, 2000, 0)] = true
}, 1003, 2000, 20, standingOf)
check("a vanilla phone never rings", rings, nil)

stands.c = true
rings = Core.phoneToRing(spotsOf(), {
    [Core.phoneKey(1000, 2000, 0)] = true,
    [Core.phoneKey(1010, 2000, 0)] = true
}, 1003, 2000, 20, standingOf)
check("until the swap reaches us", rings and rings.x, 1015)

check("out of range nothing rings", Core.phoneToRing(spotsOf(), {}, 1500, 2000, 20, standingOf), nil)
check("no range, nothing rings", Core.phoneToRing(spotsOf(), {}, 1003, 2000, 0, standingOf), nil)

-- ---------------------------------------------------------------------------
-- A point registered with a phone: the phone stands behind it, is recorded
-- under the point's id, and is put back rather than forgotten.
-- ---------------------------------------------------------------------------
reset()
check("a bad phone facing is refused", Core.registerPoint("d.bad", {label = "Bad", x = 1, y = 1, phone = "up"}), nil)
check("and not registered", Core.points["d.bad"], nil)

local declared = Core.registerPoint("d.diner", {
    label = "Diner",
    x = 3001,
    y = 3000,
    discovery = Core.discovery.start,
    phone = "E"
})
check("a point with a phone registers", declared ~= nil, true)
check("its phone stands behind it", declared and declared.phoneKey, "3000_3000_0")
check("and keeps its own discovery", declared and declared.discovery, "start")
check("it is not a pay phone's point", Core.isPhonePoint(declared), false)

PhoneSwap.syncDeclared()
local drec = PhoneSwap.store()["3000_3000_0"]
check("the sync records its phone", drec ~= nil, true)
check("owned by the point", drec and drec.point, "d.diner")
check("facing the way it said", drec and drec.facing, "E")
check("with no point of its own", Core.points["phun.spawn.phone.3000_3000_0"], nil)
check("the key finds the point's id", PhoneSwap.idOf("3000_3000_0"), "d.diner")
check("and the id finds the key", PhoneSwap.keyOfPoint("d.diner"), "3000_3000_0")
check("an ordinary point has no key", PhoneSwap.keyOfPoint("a.explore"), nil)
check("it is never forgotten", PhoneSwap.forget(3000, 3000, 0), false)
check("and it counts for spacing", PhoneSwap.farEnough(3100, 3000), false)

-- A square loading without it puts one up, over nothing.
local puts = {}
local realReplace = PhoneSwap.replace
PhoneSwap.replace = function(square, old, spriteName)
    table.insert(puts, {old = old, sprite = spriteName})
    return true
end
local function emptySquare(x, y, z)
    return {
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return z end,
        getObjects = function()
            return {size = function() return 0 end}
        end
    }
end
PhoneSwap.ready = true
PhoneSwap.loadGridsquare(emptySquare(3000, 3000, 0))
check("an empty square gets its phone", #puts, 1)
check("facing east", puts[1] and puts[1].sprite, "phuninteriors_01_16")
check("and the record is still there", PhoneSwap.store()["3000_3000_0"] ~= nil, true)
PhoneSwap.loadGridsquare(emptySquare(3050, 3000, 0))
check("a square with nothing asked for is left alone", #puts, 1)
PhoneSwap.replace = realReplace

-- Using it grants the point, which a start point already is.
local dan = stubs.player("dan", 5)
dan.moveTo(3001, 3000, 0)
got, why = PhoneSwap.use(dan, {x = 3000, y = 3000, z = 0})
check("using it answers with the point", got and got.id, "d.diner")
check("already known, as a start point", why, false)

-- A swapped phone already standing where a point asks for one is taken over.
PhoneSwap.add(4000, 4000, 0, "S")
check("a swapped phone has its own point", Core.points["phun.spawn.phone.4000_4000_0"] ~= nil, true)
Core.registerPoint("d.station", {label = "Station", x = 4000, y = 4001, phone = "S"})
PhoneSwap.syncDeclared()
check("the point takes it over", PhoneSwap.store()["4000_4000_0"].point, "d.station")
check("and its own point goes", Core.points["phun.spawn.phone.4000_4000_0"], nil)
check("keeping its facing", PhoneSwap.store()["4000_4000_0"].facing, "S")

-- The point going leaves the phone as an ordinary one, and coming back takes
-- it again.
Core.removePoint("d.station")
PhoneSwap.syncDeclared()
check("a point gone lets its phone go", PhoneSwap.store()["4000_4000_0"].point, nil)
check("which is a pay phone again", Core.points["phun.spawn.phone.4000_4000_0"] ~= nil, true)
check("and could be forgotten", PhoneSwap.store()["4000_4000_0"] ~= nil, true)
Core.registerPoint("d.station", {label = "Station", x = 4000, y = 4001, phone = "S"})
PhoneSwap.syncDeclared()
check("back again, it takes it over again", PhoneSwap.store()["4000_4000_0"].point, "d.station")

-- A restart registers no pay phone point for a phone a point owns.
Core.points = {}
Core.indexesBuilt = false
Core.registerPoint("d.diner", {label = "Diner", x = 3001, y = 3000, discovery = Core.discovery.start, phone = "E"})
Core.registerPoint("d.station", {label = "Station", x = 4000, y = 4001, phone = "S"})
PhoneSwap.start()
check("after a restart the diner owns its phone", PhoneSwap.store()["3000_3000_0"].point, "d.diner")
check("and no pay phone point was made for it", Core.points["phun.spawn.phone.3000_3000_0"], nil)
check("nor for the station's", Core.points["phun.spawn.phone.4000_4000_0"], nil)
PhoneSwap.ready = false

-- ---------------------------------------------------------------------------
-- The pool: every square a phone may go on, ranked once per world and taken
-- in rank order, each spaced against every phone standing and every one
-- taken before it. Only a pending phone ever moves.
--
-- Ranks are set by hand here. A rank's last two digits are its chance roll,
-- and every rank below ends in 00, so each passes any chance.
-- ---------------------------------------------------------------------------
check("a bad facing is not a candidate", Core.addPhoneCandidate(1, 1, 0, "up"), false)
check("nor a chance of 0", Core.addPhoneCandidate(1, 1, 0, "S", 0), false)
check("nor one over 100", Core.addPhoneCandidate(1, 1, 0, "S", 101), false)
check("nor a square with no x", Core.addPhoneCandidate(nil, 1, 0, "S"), false)
check("nor mods that are not a list", Core.addPhoneCandidate(1, 1, 0, "S", nil, "somemap"), false)
check("a candidate for an absent mod is not added", Core.addPhoneCandidate(2, 1, 0, "S", nil, {"somemap"}), false)
check("so it is not offered", Core.phones.candidates["2_1_0"], nil)
check("nor is a map phone for one", Core.addMapPhone(4, 1, 0, "S", {"somemap"}), false)
stubs.mods = {somemap = true}
check("one for an active mod is", Core.addPhoneCandidate(3, 1, 0, "S", nil, {"absent", "somemap"}), true)
check("and offered", Core.phones.candidates["3_1_0"] ~= nil, true)
check("a map phone for one is", Core.addMapPhone(4, 1, 0, "S", {"somemap"}), true)
check("replacing only", Core.phones.candidates["4_1_0"].replace, true)
check("at PhoneChance, not a percent of its own", Core.phones.candidates["4_1_0"].chance, nil)
check("a map phone does not replace a spot", Core.addMapPhone(3, 1, 0, "E"), false)
check("the spot stays", Core.phones.candidates["3_1_0"].replace, nil)
check("a spot replaces a map phone", Core.addPhoneCandidate(4, 1, 0, "E"), true)
check("which is a spot now", Core.phones.candidates["4_1_0"].replace, nil)
stubs.mods = {}

reset()
Core.phones.candidates = {}
Core.settings.PhoneChance = 100
local function ranks(list)
    Core.data.phoneRanks = Core.data.phoneRanks or {}
    for key, rank in pairs(list) do
        Core.data.phoneRanks[key] = rank
    end
end
local function takenFrom(order)
    local i = 0
    return function()
        i = i + 1
        return order[i] or 0
    end
end
-- 1000 and 1200 are 200 apart, so one gap; 3000 is on its own; 6000 is a
-- map phone.
Core.addPhoneCandidate(1000, 5000, 0, "S")
Core.addPhoneCandidate(1200, 5000, 0, "S")
Core.addPhoneCandidate(3000, 5000, 0, "E")
Core.addMapPhone(6000, 5000, 0, "S")
check("a candidate is stored under its square", Core.phones.candidates["1000_5000_0"] ~= nil, true)
check("with a chance of 100 by default", Core.phones.candidates["1000_5000_0"].chance, 100)

PhoneSwap.start()
check("start takes nothing", PhoneSwap.store()["1000_5000_0"], nil)
-- New squares are ranked in key order: 1000, 1200, 3000, 6000.
PhoneSwap.resolve(takenFrom({100, 200, 300, 400}))
check("each square is ranked once", Core.data.phoneRanks["1200_5000_0"], 200)
local crec = PhoneSwap.store()["1000_5000_0"]
check("the first of a gap is taken", crec ~= nil, true)
check("as pending", crec and crec.pending, true)
check("the next is too close", PhoneSwap.store()["1200_5000_0"], nil)
check("one on its own is taken", PhoneSwap.store()["3000_5000_0"] ~= nil, true)
check("and so is a map phone", PhoneSwap.store()["6000_5000_0"] ~= nil, true)
check("a taken one is a point already", Core.points["phun.spawn.phone.1000_5000_0"] ~= nil, true)
check("in front of its phone", Core.points["phun.spawn.phone.1000_5000_0"].y, 5001)
check("found by use, like any phone", Core.points["phun.spawn.phone.1000_5000_0"].discovery, "used")
check("a taken one reserves its spacing", PhoneSwap.farEnough(1300, 5000), false)
check("it is not forgotten before it goes up", PhoneSwap.forget(1000, 5000, 0), false)
check("nothing changed, nothing runs", PhoneSwap.resolve(takenFrom({0, 0, 0, 0})), false)
check("and the ranks stay", Core.data.phoneRanks["1000_5000_0"], 100)

-- A phone standing near a pending one pushes it off the gap.
PhoneSwap.add(1000, 5100, 0, "S")
PhoneSwap.resolve()
check("a pending phone gives way to one standing", PhoneSwap.store()["1000_5000_0"], nil)
check("with its point", Core.points["phun.spawn.phone.1000_5000_0"], nil)
check("and the gap has no room for the next", PhoneSwap.store()["1200_5000_0"], nil)
PhoneSwap.store()["1000_5100_0"] = nil
PhoneSwap.touch()
PhoneSwap.resolve()
check("gone again, the first takes its place back", PhoneSwap.store()["1000_5000_0"] ~= nil, true)

-- A new world: the ranks went with the ModData, and other ranks take
-- another phone from the same gap.
Core.data = {}
Core.points = {}
Core.indexesBuilt = false
PhoneSwap.start()
PhoneSwap.resolve(takenFrom({900, 100, 300, 400}))
check("another world, another winner", PhoneSwap.store()["1200_5000_0"] ~= nil, true)
check("and the first is not", PhoneSwap.store()["1000_5000_0"], nil)
check("one on its own still is", PhoneSwap.store()["3000_5000_0"] ~= nil, true)

-- A late candidate is ranked when it turns up, and its chance is its rank.
Core.addPhoneCandidate(8000, 5000, 0, "N", 1)
PhoneSwap.resolve(takenFrom({50}))
check("a late candidate is ranked", Core.data.phoneRanks["8000_5000_0"], 50)
check("and a failed chance takes nothing", PhoneSwap.store()["8000_5000_0"], nil)

-- A square already holding a phone of ours is that phone's.
PhoneSwap.add(9000, 5000, 0, "W")
Core.addPhoneCandidate(9000, 5000, 0, "S")
PhoneSwap.resolve(takenFrom({0}))
check("a candidate on a phone leaves it as it was", PhoneSwap.store()["9000_5000_0"].facing, "W")
check("not pending", PhoneSwap.store()["9000_5000_0"].pending, nil)

-- Squares loading. A spot goes up on nothing; a map phone only over the
-- vanilla phone it names, and faces the way that one does.
PhunZones = {
    inied = true,
    getLocation = function()
        return {title = "Nowhere", subtitle = "Farm"}
    end
}
puts = {}
PhoneSwap.replace = function(square, old, spriteName)
    table.insert(puts, {old = old, sprite = spriteName})
    return true
end
PhoneSwap.ready = true
PhoneSwap.loadGridsquare(emptySquare(1200, 5000, 0))
check("a spot's square loading puts the phone up", #puts, 1)
check("facing the way it was offered", puts[1] and puts[1].sprite, "phuninteriors_01_17")
check("it is no longer pending", PhoneSwap.store()["1200_5000_0"].pending, nil)
check("its place is looked up as it goes up", Core.points["phun.spawn.phone.1200_5000_0"].region, "Nowhere")
PhoneSwap.loadGridsquare(emptySquare(1000, 5000, 0))
check("a square not taken is left alone", #puts, 1)

PhoneSwap.loadGridsquare(squareWith(6000, 5000, 0, "street_decoration_01_38"))
check("a map phone goes up over the vanilla one", #puts, 2)
check("replacing it", puts[2] and puts[2].old ~= nil, true)
check("facing the way it does", puts[2] and puts[2].sprite, "phuninteriors_01_16")
check("and is recorded so", PhoneSwap.store()["6000_5000_0"].facing, "E")
check("its point moved to the front of it", Core.points["phun.spawn.phone.6000_5000_0"].x, 6001)

-- A map phone whose square has none is dropped, and the next in rank near it
-- takes its place.
Core.addMapPhone(7000, 9000, 0, "S")
Core.addMapPhone(7100, 9000, 0, "S")
ranks({["7000_9000_0"] = 100, ["7100_9000_0"] = 200})
PhoneSwap.resolve()
check("the first map phone is taken", PhoneSwap.store()["7000_9000_0"] ~= nil, true)
check("the second is too near", PhoneSwap.store()["7100_9000_0"], nil)
PhoneSwap.loadGridsquare(emptySquare(7000, 9000, 0))
check("nothing to replace puts nothing up", #puts, 2)
check("and drops it", PhoneSwap.store()["7000_9000_0"], nil)
check("for the world", Core.data.phoneDropped["7000_9000_0"], true)
PhoneSwap.loadGridsquare(emptySquare(1, 1, 0))
check("the next in rank takes its place", PhoneSwap.store()["7100_9000_0"] ~= nil, true)
PhoneSwap.loadGridsquare(emptySquare(1, 1, 0))
check("and a dropped square is not taken again", PhoneSwap.store()["7000_9000_0"], nil)

-- One of ours carried off a pool square is forgotten and retired, so the
-- next in rank takes its place rather than it coming back.
Core.addPhoneCandidate(1100, 5000, 0, "S")
ranks({["1100_5000_0"] = 999900})
PhoneSwap.loadGridsquare(emptySquare(1, 1, 0))
check("a candidate in a full gap waits", PhoneSwap.store()["1100_5000_0"], nil)
PhoneSwap.loadGridsquare(emptySquare(1200, 5000, 0))
check("a standing phone carried off is forgotten", PhoneSwap.store()["1200_5000_0"], nil)
check("and retired", Core.data.phoneDropped["1200_5000_0"], true)
PhoneSwap.loadGridsquare(emptySquare(1, 1, 0))
check("the gap's next in rank takes its place", PhoneSwap.store()["1000_5000_0"] ~= nil, true)
check("not the one ranked after it", PhoneSwap.store()["1100_5000_0"], nil)
check("and not the one carried off", PhoneSwap.store()["1200_5000_0"], nil)

-- Taken while its square is loaded, it goes up at once rather than waiting
-- for the square to load again.
local loaded = {["2000_7000_0"] = emptySquare(2000, 7000, 0)}
local cellBefore = getCell
getCell = function()
    return {getGridSquare = function(_, x, y, z) return loaded[x .. "_" .. y .. "_" .. z] end}
end
Core.addPhoneCandidate(2000, 7000, 0, "W")
ranks({["2000_7000_0"] = 100})
PhoneSwap.loadGridsquare(emptySquare(1, 1, 0))
check("a square already loaded gets its phone at once", PhoneSwap.store()["2000_7000_0"].pending, nil)
getCell = cellBefore
PhoneSwap.replace = realReplace

-- A pending one taken out of the code is let go; a standing one stays, as
-- any phone does.
Core.phones.candidates["3000_5000_0"] = nil
Core.phones.candidates["6000_5000_0"] = nil
Core.phones.candidatesVersion = Core.phones.candidatesVersion + 1
PhoneSwap.resolve()
check("a pending one taken out is let go", PhoneSwap.store()["3000_5000_0"], nil)
check("with its point", Core.points["phun.spawn.phone.3000_5000_0"], nil)
check("a standing one taken out stays", PhoneSwap.store()["6000_5000_0"] ~= nil, true)
check("and could be forgotten now", PhoneSwap.forget(6000, 5000, 0), true)

-- The client is told of the phones standing that the pool does not name.
local function sentKeys()
    local out = {}
    for _, key in ipairs(PhoneSwap.standingKeys()) do
        out[key] = true
    end
    return out
end
check("a phone on a pool square is not sent", sentKeys()["1000_5000_0"], nil)
PhoneSwap.add(9500, 5000, 0, "W")
check("one standing off the pool is", sentKeys()["9500_5000_0"], true)
PhoneSwap.ready = false
Core.phones.candidates = {}
Core.phones.candidatesVersion = Core.phones.candidatesVersion + 1
PhunZones = nil

-- ---------------------------------------------------------------------------
-- The guards, installed over stand-ins for the vanilla classes. What matters
-- here is the routing: our phones are refused, anything else reaches vanilla
-- untouched, and admin mode reaches vanilla too. A guard that forgot to call
-- through would break every moveable in the game, and that is worth a spec.
-- ---------------------------------------------------------------------------
local function spriteOf(name)
    return {
        getName = function()
            return name
        end
    }
end
local function objectOf(name)
    return {
        getSprite = function()
            return spriteOf(name)
        end
    }
end
local function characterOf(movables, build)
    return {
        isMovablesCheat = function()
            return movables == true
        end,
        isBuildCheat = function()
            return build == true
        end,
        setHaloNote = function()
        end
    }
end

local vanillaCalls = 0
local function vanilla()
    vanillaCalls = vanillaCalls + 1
    return true
end
ISMoveableSpriteProps = {
    canPickUpMoveable = vanilla,
    canScrapObject = function()
        vanillaCalls = vanillaCalls + 1
        return {canScrap = true}, 100, "Woodwork"
    end
}
ISMoveablesAction = {isValid = vanilla}
ISDestroyStuffAction = {isValid = vanilla}
ISDestroyCursor = {canDestroy = vanilla}
local unset = {}
function getSprite(name)
    return {
        getProperties = function()
            return {
                has = function(_, key)
                    return key == "HitByCar" and not unset[name]
                end,
                unset = function(_, key)
                    unset[name] = key
                end
            }
        end
    }
end
function getTimestampMs()
    return 0
end
require "PhunTaxi/phone_guards"
Core.installPhoneGuards()

local player = characterOf(false, false)
local admin = characterOf(true, false)
local builder = characterOf(false, true)
local phoneProps = setmetatable({sprite = spriteOf("phuninteriors_01_17")}, {__index = ISMoveableSpriteProps})
local chairProps = setmetatable({sprite = spriteOf("furniture_01_1")}, {__index = ISMoveableSpriteProps})

check("HitByCar is taken off our phones", unset["phuninteriors_01_16"], "HitByCar")
check("on every facing", unset["phuninteriors_01_19"], "HitByCar")
check("and left on vanilla tiles", unset["street_decoration_01_38"], nil)

check("admin mode is the movables cheat", Core.phoneAdminMode(admin), true)
check("or the build cheat", Core.phoneAdminMode(builder), true)
check("and not being a player", Core.phoneAdminMode(player), false)

vanillaCalls = 0
check("a player cannot pick up a phone", phoneProps:canPickUpMoveable(player), false)
check("without asking vanilla", vanillaCalls, 0)
check("a player can pick up a chair", chairProps:canPickUpMoveable(player), true)
check("an admin can pick up a phone", phoneProps:canPickUpMoveable(admin), true)
check("both through vanilla", vanillaCalls, 2)

local result = phoneProps:canScrapObject(player)
check("a player cannot dismantle a phone", result.canScrap, false)
result = phoneProps:canScrapObject(admin)
check("an admin can", result.canScrap, true)
result = chairProps:canScrapObject(player)
check("and a chair is untouched", result.canScrap, true)

local function actionOf(mode, name, character)
    return setmetatable({
        mode = mode,
        character = character,
        moveProps = {sprite = spriteOf(name)},
        stop = function()
        end
    }, {__index = ISMoveablesAction})
end
check("a pickup action on a phone is refused", actionOf("pickup", "phuninteriors_01_16", player):isValid(), false)
check("so is a rotate", actionOf("rotate", "phuninteriors_01_16", player):isValid(), false)
check("so is a scrap", actionOf("scrap", "phuninteriors_01_16", player):isValid(), false)
check("placing one is allowed", actionOf("place", "phuninteriors_01_16", player):isValid(), true)
check("an admin's pickup goes through", actionOf("pickup", "phuninteriors_01_16", admin):isValid(), true)
check("a chair's pickup goes through", actionOf("pickup", "furniture_01_1", player):isValid(), true)

local function destroyOf(name, character)
    return setmetatable({item = objectOf(name), character = character}, {__index = ISDestroyStuffAction})
end
check("a sledgehammer on a phone is refused", destroyOf("phuninteriors_01_18", player):isValid(), false)
check("unless in admin mode", destroyOf("phuninteriors_01_18", builder):isValid(), true)
check("a sledgehammer on anything else is vanilla's", destroyOf("furniture_01_1", player):isValid(), true)

local cursor = setmetatable({character = player}, {__index = ISDestroyCursor})
check("the destroy cursor skips a phone", cursor:canDestroy(objectOf("phuninteriors_01_19")), false)
check("and offers anything else", cursor:canDestroy(objectOf("furniture_01_1")), true)

-- ---------------------------------------------------------------------------
-- The shipped spots are candidates, drawn and spaced, not kept phones every
-- world gets all of. Offered on the phone's square, behind the traveller's.
-- ---------------------------------------------------------------------------
reset()
Core.phones.candidates = {}
Core.shipped = {}
require "PhunTaxi/defaults"
local offered = 0
for _ in pairs(Core.phones.candidates) do
    offered = offered + 1
end
check("the shipped spots are offered", offered > 0, true)
check("on the phone's square", Core.phones.candidates["10620_9366_0"] ~= nil, true)
check("not the traveller's", Core.phones.candidates["10620_9367_0"], nil)
local Store = require "PhunTaxi/store"
check("the shipped list reads clean", #Store.readShipped(), 0)
local keeps = 0
for _ in pairs(Store.shipped.phones) do
    keeps = keeps + 1
end
check("and keeps no phone", keeps, 0)
check("a winner is named", Store.shippedLabel(Core.phonePointId(10620, 9366, 0)), "Storage")
check("a spot needing a map mod is not offered without it", Core.phones.candidates["10646_11061_0"], nil)

-- The map phones, as the server loads them: before the spots.
Core.phones.candidates = {}
Core.shipped = {}
require "PhunTaxi/map_phones"
-- Already required above, and the stub require runs a file once.
dofile(ROOT .. "/Contents/mods/PhunTaxi/common/media/lua/shared/PhunTaxi/defaults.lua")
local maps, spots = 0, 0
for _, c in pairs(Core.phones.candidates) do
    if c.replace then
        maps = maps + 1
    else
        spots = spots + 1
    end
end
check("the vanilla map phones are offered", maps > 300, true)
check("as map phones", Core.phones.candidates["420_9872_0"] and Core.phones.candidates["420_9872_0"].replace, true)
check("a map mod's are not without it", Core.phones.candidates["4286_15491_0"], nil)
check("and the spots are still there", spots > 50, true)

-- A resolve over the whole shipped pool, timed, since it runs in game on a
-- square load. LuaJIT is far faster than Kahlua, so this is only a ceiling
-- on the work, not a measure of the hitch.
reset()
Core.settings.PhoneChance = 100
Core.settings.PhoneDistance = 300
PhoneSwap.start()
local began = os.clock()
PhoneSwap.resolve(function(n)
    return math.random(0, n - 1)
end)
local took = os.clock() - began
local taken = 0
for _, record in pairs(PhoneSwap.store()) do
    if record.pending then
        taken = taken + 1
    end
end
check("the whole pool resolves to a spaced set", taken > 40 and taken < maps, true)
check("in well under a tenth of a second here", took < 0.1, true)
print(string.format("  whole pool: %d map phones, %d spots, %d taken at 300, %.1f ms", maps, spots, taken,
    took * 1000))
Core.phones.candidates = {}
Core.shipped = {}

-- ---------------------------------------------------------------------------
-- tools.sort, which resolve and the points list use because Kahlua's
-- table.sort recursed into a stack overflow on the pool's thousand keys.
-- ---------------------------------------------------------------------------
local sortOk = true
for _, n in ipairs({0, 1, 2, 3, 7, 64, 1000, 5001}) do
    local list, want = {}, {}
    for i = 1, n do
        list[i] = tostring(math.random(1, 100000)) .. "_" .. i
        want[i] = list[i]
    end
    table.sort(want)
    Core.tools.sort(list)
    for i = 1, n do
        if list[i] ~= want[i] then
            sortOk = false
        end
    end
end
check("tools.sort agrees with table.sort at every size", sortOk, true)
local desc = Core.tools.sort({3, 1, 2}, function(a, b) return a > b end)
check("with a comparator", table.concat(desc, ","), "3,2,1")
local pairsList = {{k = 1, v = "a"}, {k = 0, v = "b"}, {k = 1, v = "c"}, {k = 0, v = "d"}}
Core.tools.sort(pairsList, function(a, b) return a.k < b.k end)
check("and stable", pairsList[1].v .. pairsList[2].v .. pairsList[3].v .. pairsList[4].v, "bdac")

os.exit(report.finish("phones") == 0 and 0 or 1)
