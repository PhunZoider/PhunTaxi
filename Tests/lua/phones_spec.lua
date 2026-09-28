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
    Core.saved = {points = {}, phones = {}, labels = {}}
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
-- A swapped phone is a point, in front of the phone, found by using it.
-- ---------------------------------------------------------------------------
reset()
PhunZones = {
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
check("label names the place and square", point and point.label, "Downtown pay phone (1000, 2000)")
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
check("and a plain label", point and point.label, "Pay phone (5000, 5000)")

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

PhoneSwap.ready = true
PhoneSwap.loadGridsquare(placed["1090_2000_0"])
check("a placed phone is recorded on load", Core.points["phun.spawn.phone.1090_2000_0"] ~= nil, true)
check("facing west", PhoneSwap.store()["1090_2000_0"].facing, "W")
PhoneSwap.ready = false
getCell = realGetCell
bob.moveTo(1000, 2001, 0)

-- The location is looked at again on use, for a phone that swapped before
-- PhunZones was ready.
PhunZones = {
    getLocation = function()
        return {
            title = "West Point"
        }
    end
}
PhoneSwap.use(bob, {x = 1000, y = 2000, z = 0})
check("use refreshes the region", Core.points["phun.spawn.phone.1000_2000_0"].region, "West Point")

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
PhoneSwap.add(4000, 4000, 0, "S", "phuninteriors_01_17")
check("a swapped phone has its own point", Core.points["phun.spawn.phone.4000_4000_0"] ~= nil, true)
Core.registerPoint("d.station", {label = "Station", x = 4000, y = 4001, phone = "S"})
PhoneSwap.syncDeclared()
check("the point takes it over", PhoneSwap.store()["4000_4000_0"].point, "d.station")
check("and its own point goes", Core.points["phun.spawn.phone.4000_4000_0"], nil)
check("keeping its sprite", PhoneSwap.store()["4000_4000_0"].sprite, "phuninteriors_01_17")

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

os.exit(report.finish("phones") == 0 and 0 or 1)
