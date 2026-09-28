if isClient() then
    return
end
require "PhunSpawn/points"
require "PhunSpawn/interiors"
local Core = PhunSpawn
local Unlocks = require "PhunSpawn/unlocks"
local Placement = require "PhunSpawn/placement"
local Arrival = {}

-- ---------------------------------------------------------------------------
-- Putting a new character in the arrival room.
--
-- Wherever vanilla put them does not matter, because this moves them: the
-- first time the server sees a pending character, it asks PhunInteriors for a
-- slot of the arrival room and puts them in it. So the vanilla spawn selector
-- is only ever deciding which square a character stands on for a moment, and
-- collapsing it to one region (below) is tidiness, not the mechanism.
--
-- The room is SHARED when every slot is taken. A server may only ever have
-- one spawn room, and two new characters in one room is fine; a new character
-- refused a room is not. PhunInteriors decides which slot and whether to
-- share, and holds the lease: nothing here keeps a copy of either, for the
-- reason nothing here teleports.
--
-- The only way out is the taxi, which is the spawn command, which is
-- PhunInteriors.sendTo with release. Asked for with `exit = false`, so there
-- is no "Step outside" to walk out of a free choice with. `returnTo` is still
-- passed, for PhunInteriors' own rescue of somebody stranded in a slot.
--
-- TODO: PhunInteriors.enterRoom does not exist yet; this is written against
-- the brief for it. Until it does, a pending character is placed at their
-- fallback point instead, which is what UseSpawnRoom's tooltip promises when
-- the room is unavailable.
-- ---------------------------------------------------------------------------

-- Where a new character stands for the moment before they are moved: the
-- one point every vanilla spawn region collapses to. It must be a real,
-- walkable square OUTSIDE every slot of every room: a character landing in a
-- slot with no lease is put back outside by PhunInteriors' rescueStranded,
-- and two landing on one slot would share it by accident. Off grid, in the
-- phuninteriors cell, so nothing out there sees them arrive.
--
-- The middle of cell 87,49 (x 22272..22526, y 12544..12798 inside the fence),
-- well clear of the one arrival slot at 22276..22284, 12565..12574. Set to nil
-- to leave the vanilla selector alone; a new character is then moved from
-- wherever they chose, which works and only looks untidy.
--
-- TODO: unchecked in game that the square is open floor.
Arrival.landing = {
    x = 22400,
    y = 12672,
    z = 0
}

-- Characters already admitted this session, by player key. playerSetup is
-- also the picker's refresh, so without this every opening of the picker
-- would ask PhunInteriors to admit somebody already inside. It is only a
-- shortcut: PhunInteriors is asked again after a restart, and answers for a
-- character already in the room without moving them.
local admitted = {}

--- Where a character goes when there is no room for them, and where the
--- room's rescue puts them: their last choice if they still know it, else the
--- first start point they know. Nil if they know nothing.
function Arrival.fallback(player)
    local last = Unlocks.lastChoice(player)
    if last and Unlocks.has(player, last) then
        return Core.points[last]
    end
    -- Sorted by id so the same account gets the same answer twice; pairs()
    -- order is not an answer.
    local ids = {}
    for id, point in pairs(Core.points) do
        if point.discovery == Core.discovery.start then
            table.insert(ids, id)
        end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        if Unlocks.has(player, id) then
            return Core.points[id]
        end
    end
    return nil
end

--- Place a pending character at a point, as the spawn command would, and use
--- up their choice. Only for when the room cannot have them: a character with
--- no room and no way out of where they landed is worse than one who skipped
--- the picker.
local function placeAt(player, point)
    if not (PhunInteriors and PhunInteriors.sendTo) then
        return false
    end
    local ok, why = PhunInteriors.sendTo(player, {
        x = point.x,
        y = point.y,
        z = point.z
    }, "phunspawn", true)
    if not ok then
        Core.logLn("fallback to " .. point.id .. " refused by PhunInteriors: " .. tostring(why))
        return false
    end
    Placement.markSpawned(player)
    Unlocks.setLastChoice(player, point.id)
    Core.respond(player, Core.commands.notify, {
        text = "IGUI_PhunSpawn_WokeUp",
        arg = point.label
    })
    triggerEvent(Core.events.OnSpawned, player, point)
    return true
end

--- Put a pending character in the arrival room, or at their fallback point
--- if there is no room for them.
--
-- Returns "room", "fallback", or nil plus why nothing happened. Nothing is
-- the right answer for an established character, for one already admitted,
-- and with UseSpawnRoom off: they are exactly where they should be.
function Arrival.admit(player)
    if not player then
        return nil, "no player"
    end
    if not Core.settings.UseSpawnRoom then
        return nil, "off"
    end
    local key = Core.playerKey(player)
    if admitted[key] then
        return nil, "admitted"
    end
    if not Placement.isPending(player) then
        return nil, "placed"
    end

    local fallback = Arrival.fallback(player)
    local why
    if PhunInteriors and PhunInteriors.enterRoom then
        local ok
        ok, why = PhunInteriors.enterRoom(player, Core.roomIds.arrival, {
            reason = "phunspawn",
            share = true,
            exit = false,
            returnTo = fallback and {
                x = fallback.x,
                y = fallback.y,
                z = fallback.z
            } or nil
        })
        if ok then
            admitted[key] = true
            Core.debugLn(tostring(key) .. " admitted to " .. Core.roomIds.arrival .. " (" .. tostring(why) .. ")")
            return "room"
        end
    else
        why = "PhunInteriors.enterRoom is missing; PhunInteriors is older than this version of PhunSpawn needs"
    end
    Core.logLn("no arrival room for " .. tostring(key) .. ": " .. tostring(why))

    if fallback and placeAt(player, fallback) then
        admitted[key] = true
        return "fallback"
    end
    -- Left where they landed, still pending. Not stamped as admitted, so the
    -- next playerSetup tries again: a room that comes free, or a point they
    -- come to know, gets them out.
    return nil, why
end

--- Collapse every vanilla spawn region to the landing square, so the vanilla
--- selector has one choice and skips itself.
--
-- Server side only, and that is enough for a server: OnSpawnRegionsLoaded
-- fires where the regions are built, and a client is sent the server's.
-- Emptied and refilled IN PLACE, because the caller returns the table it
-- passed to the event and ignores anything a listener returns.
--
-- It does not reach vanilla's safehouse respawn, which the client asks
-- before any region and is left alone on purpose. Nor single player, whose
-- selector runs in the main menu before this file loads; there a new
-- character is moved from wherever they chose.
function Arrival.collapseRegions(regions)
    local at = Arrival.landing
    -- The option read here rather than from Core.settings: the server may
    -- build its regions before OnInitGlobalModData has filled the cache, and
    -- an empty cache reads as "off".
    if not (regions and at and Core.getOption("UseSpawnRoom", true)) then
        return false
    end
    for i = #regions, 1, -1 do
        regions[i] = nil
    end
    -- `unemployed` is the list vanilla falls back on for every profession;
    -- its own fixed server spawn point is built the same way.
    regions[1] = {
        name = "PhunSpawn",
        points = {
            unemployed = {{
                posX = at.x,
                posY = at.y,
                posZ = at.z or 0
            }}
        }
    }
    return true
end

Core.modules.arrival = Arrival
return Arrival
