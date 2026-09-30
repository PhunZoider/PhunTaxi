-- The PhunZones hook: the Taxi Garage zone.
--
-- Whether PhunZones enforces any of it is tested in game or not at all. What
-- is here is what fails without a sound: a rect a square short of the cell, a
-- flag spelled the way PhunZones does not read it, and a zone added when
-- PhunZones is not there to take it.
local ROOT = os.getenv("PS_ROOT") or "."
local stubs = dofile(ROOT .. "/Tests/lua/stubs.lua")
stubs.install(ROOT)

local report = stubs.reporter()
local check = report.check

local active = {}
function getActivatedMods()
    return {contains = function(_, id) return active[id] == true end}
end

-- PhunZones' table, fresh for each load. The stubs' require caches by path,
-- so zones.lua is run directly rather than required.
local data
local stubRequire = require
function require(path)
    if path == "PhunZones/data" then
        return data
    end
    if path == "PhunZones/core" then
        return PhunZones
    end
    return stubRequire(path)
end
local zonesFile = ROOT .. "/Contents/mods/PhunTaxi/common/media/lua/shared/PhunTaxi/zones.lua"

local function load(mods)
    active = mods
    data = {}
    PhunZones = {fields = {}}
    dofile(zonesFile)
    return data
end

-- ---------------------------------------------------------------------------
-- Without PhunZones: nothing is asked of it.
-- ---------------------------------------------------------------------------
data = load({})
check("no PhunZones, no zone", data.PhunTaxi_TaxiGarage, nil)

-- ---------------------------------------------------------------------------
-- With it, under either id.
-- ---------------------------------------------------------------------------
for _, id in ipairs({"phunzones2", "phunzones2test"}) do
    data = load({[id] = true})
    check(id .. " adds the zone", data.PhunTaxi_TaxiGarage ~= nil, true)
end

local zone = load({phunzones2 = true}).PhunTaxi_TaxiGarage
check("title", zone.title, "Taxi Garage")
check("zeds removed", zone.zeds, "remove")
for _, flag in ipairs({"nosafehouse", "nobuilding", "noplacing", "nopickup", "noscrap", "nodestruction"}) do
    check(flag, zone[flag], true)
end
check("outranks implicit orders", type(zone.order) == "number" and zone.order > 0, true)

-- Cell 87,49 exactly, inclusive at both ends as PhunZones' getLocation reads
-- a rect.
check("one rect", #zone.points, 1)
local r = zone.points[1]
check("x1 is the cell's west edge", r[1], 87 * 256)
check("y1 is the cell's north edge", r[2], 49 * 256)
check("x2 is the cell's last column", r[3], 88 * 256 - 1)
check("y2 is the cell's last row", r[4], 50 * 256 - 1)

-- The same ground the map's NoPowerOrWater zone covers, which is the other
-- place these numbers are written down.
local objects = io.open(ROOT .. "/Contents/mods/PhunTaxi/common/media/maps/phuntaxi/objects.lua"):read("*a")
local ox, oy, ow, oh = objects:match("x = (%d+), y = (%d+), z = %d+, width = (%d+), height = (%d+)")
check("matches objects.lua x", r[1], tonumber(ox))
check("matches objects.lua y", r[2], tonumber(oy))
check("matches objects.lua width", r[3] - r[1] + 1, tonumber(ow))
check("matches objects.lua height", r[4] - r[2] + 1, tonumber(oh))

-- ---------------------------------------------------------------------------
-- The pay phone fields, added to PhunZones' editor only when it is there.
-- ---------------------------------------------------------------------------
local chanceField = PhunTaxi.consts.zoneChanceField
local distanceField = PhunTaxi.consts.zoneDistanceField
load({})
check("no PhunZones, no chance field", PhunZones.fields[chanceField], nil)
load({phunzones2 = true})
for _, key in ipairs({chanceField, distanceField}) do
    local field = PhunZones.fields[key]
    check(key .. " is a field", field ~= nil, true)
    check(key .. " is an int", field and field.type, "int")
    -- A default would read as the zone setting it, and hide the sandbox value.
    check(key .. " has no default", field and field.default, nil)
end
-- Every label and tooltip is translated, or the editor shows the raw key.
local ui = io.open(ROOT .. "/Contents/mods/PhunTaxi/common/media/lua/shared/Translate/EN/IG_UI.json"):read("*a")
for _, key in ipairs({chanceField, distanceField}) do
    local field = PhunZones.fields[key]
    check(key .. " label translated", ui:find('"' .. field.label .. '"', 1, true) ~= nil, true)
    check(key .. " tooltip translated", ui:find('"' .. field.tooltip .. '"', 1, true) ~= nil, true)
end
PhunZones = nil

os.exit(report.finish("zones") == 0 and 0 or 1)
