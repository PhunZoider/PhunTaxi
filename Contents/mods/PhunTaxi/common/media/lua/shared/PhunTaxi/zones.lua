require "PhunSpawn/core"
local Core = PhunSpawn

-- ---------------------------------------------------------------------------
-- The PhunZones hook: the Taxi Garage.
--
-- A soft hook, unlike PhunInteriors. With PhunZones absent the cell is still
-- walled, unpowered and zombie free by its lotheader (see Docs/map.md), so
-- what this adds is the rest: nobody claims it, builds in it, carries it off
-- or takes it apart, and anything that does get realised in it is removed.
--
-- It is a base zone, not an admin one. PhunZones requires "PhunZones/data"
-- from core.lua and process.lua alike, so the table below is the one its
-- build merges, and an admin's own edits in the zone editor layer on top of it
-- as they would over any shipped map. Nothing is written to their config.
--
-- Added at load, not on an event, because that is the one moment guaranteed
-- to be before PhunZones' first build: Core:ini runs from OnServerStarted and
-- from the client's first tick, and every zone lookup made before then calls
-- it lazily, so a zone added any later would sit unused until the next
-- rebuild.
-- ---------------------------------------------------------------------------

-- The zone's key in PhunZones. Namespaced, since every map shares one table.
local zoneKey = "PhunSpawn_TaxiGarage"

local function phunZonesActive()
    local mods = getActivatedMods()
    return mods:contains("phunzones2") or mods:contains("phunzones2test")
end

if phunZonesActive() then
    local zones = require "PhunZones/data"
    if type(zones) == "table" then
        zones[zoneKey] = {
            title = "Taxi Garage",
            -- Above every implicitly ordered zone. PhunZones' own RV void
            -- starts at x=22500 and so covers the east edge of this cell.
            order = 100,
            -- Remove, not Move: there is nowhere in a walled cell to move one
            -- to, and nothing here but a new character who has just arrived.
            zeds = "remove",
            nosafehouse = true,
            nobuilding = true,
            noplacing = true,
            nopickup = true,
            noscrap = true,
            nodestruction = true,
            -- Cell 87,49, the whole of it. PhunZones' rects are inclusive at
            -- both ends, so this is 22272..22527, not the 256 wide
            -- NoPowerOrWater zone's half open rectangle.
            points = {{22272, 12544, 22527, 12799}}
        }
    end
end

return Core
