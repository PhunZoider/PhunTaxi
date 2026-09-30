require "PhunTaxi/core"
local Core = PhunTaxi

-- ---------------------------------------------------------------------------
-- The PhunZones hook: the Taxi Garage, and the pay phone fields any zone may
-- set (see the bottom of the file).
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
local zoneKey = "PhunTaxi_TaxiGarage"

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
            points = {{Core.consts.garage.x1, Core.consts.garage.y1, Core.consts.garage.x2, Core.consts.garage.y2}}
        }
    end

    -- Two fields any zone may set, so an admin can crowd a city with pay
    -- phones and leave the countryside sparse: PhoneChance and PhoneDistance
    -- for that zone. Added the way PhunZones' README shows a mod adding its
    -- own, into its editor's Mods group. Unset is the sandbox value, which
    -- is why there is no `default`: one would be a zone setting it.
    -- phone_swap.lua reads them, through PhunZones.getLocation.
    local ok = pcall(require, "PhunZones/core")
    local pz = PhunZones
    if ok and pz and type(pz.fields) == "table" then
        pz.fields[Core.consts.zoneChanceField] = {
            label = "IGUI_PhunTaxi_ZonePhoneChance",
            type = "int",
            tooltip = "IGUI_PhunTaxi_ZonePhoneChance_tooltip",
            group = "mods",
            order = 200,
            mod = Core.name
        }
        pz.fields[Core.consts.zoneDistanceField] = {
            label = "IGUI_PhunTaxi_ZonePhoneDistance",
            type = "int",
            tooltip = "IGUI_PhunTaxi_ZonePhoneDistance_tooltip",
            group = "mods",
            order = 201,
            mod = Core.name
        }
    end
end

return Core
