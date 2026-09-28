require "PhunSpawn/core"
require "PhunSpawn/tools"
local Core = PhunSpawn

-- ---------------------------------------------------------------------------
-- The spawn point registry.
--
-- A point is data, not arithmetic. There is deliberately no "origin plus
-- pitch times index" form: a genuinely regular set of points is a for loop in
-- the caller, and the moment somebody wants one that is not on the grid an
-- arithmetic scheme cannot describe it at all. PhunInteriors learned that the
-- expensive way with its room locations.
--
-- A point id is a key in a registry shared with third parties, so ours are
-- namespaced `phun.spawn.*` and the author docs tell everybody else to
-- namespace theirs. Re-registering your own id replaces it; re-registering
-- somebody else's is a warning and still replaces it, because a silent
-- replacement is worse than a loud one.
--
-- Every reverse index is rebuilt LAZILY, on the first read after any
-- registration. That is what lets a third party register from any vanilla
-- hook, including one that fires long after our own boot sequence, without
-- anybody having to sequence anything. Nothing here may warn about a missing
-- link at boot, because at boot it cannot tell "not registered yet" from "the
-- mod that owns it is not installed".
-- ---------------------------------------------------------------------------

-- How a point is unlocked. The value is stored on the point and read by
-- server/unlocks.lua; nothing else keys on it.
Core.discovery = {
    -- known from character creation
    start = "start",
    -- unlocked by getting within DiscoveryRadius of it
    explore = "explore",
    -- unlocked by building the thing that marks it
    built = "built",
    -- unlocked by using the thing that marks it, a pay phone. Never by
    -- walking past: see server/phone_swap.lua.
    used = "used",
    -- unlocked by something else entirely: another mod, a quest, an admin
    granted = "granted"
}

local function invalidate()
    Core.indexesBuilt = false
end

--- Register a spawn point.
--
-- @param id     namespaced string, eg "phun.spawn.muldraugh.warehouse"
-- @param def    table:
--   label       what a player sees. Required, because an id is not prose and
--               must never become prose: the label is editable and the id is
--               what a character's unlock list persists, so two strings that
--               look alike with opposite mutability is a trap.
--   x, y, z     where the character wakes up. Required.
--   region      free text, used only for grouping in the picker. Optional.
--   discovery   one of Core.discovery. Defaults to `explore`, because a point
--               that is unlocked from the start should have to say so: the
--               safe default is the one that gives nothing away.
--   room        a PhunInteriors room id, if this point wakes you up inside
--               one rather than on the square. Optional, and ignored when
--               PhunInteriors is absent.
--   priority    lower sorts first in the picker. Optional.
function Core.registerPoint(id, def)
    if type(id) ~= "string" or id == "" then
        Core.logLn("registerPoint needs a string id")
        return nil
    end
    if type(def) ~= "table" then
        Core.logLn("registerPoint('" .. id .. "') needs a definition table")
        return nil
    end
    if type(def.label) ~= "string" or def.label == "" then
        Core.logLn("registerPoint('" .. id .. "') needs a label")
        return nil
    end
    if type(def.x) ~= "number" or type(def.y) ~= "number" then
        Core.logLn("registerPoint('" .. id .. "') needs numeric x and y")
        return nil
    end

    if Core.points[id] then
        Core.logLn("point '" .. id .. "' is being redefined")
    end

    local point = {
        id = id,
        -- An admin's rename wins over what the registration says, and the
        -- registered label is kept beside it so the editor can put it back.
        label = Core.labelOverride(id) or def.label,
        shippedLabel = def.label,
        x = def.x,
        y = def.y,
        z = def.z or 0,
        region = def.region,
        discovery = def.discovery or Core.discovery.explore,
        room = def.room,
        priority = def.priority or 0,
        -- In the store file, so it survives a wipe. Set by store.lua and
        -- phone_swap.lua for what they register out of it, and shown in the
        -- editor. Not a promise a third party can make: nothing reads it to
        -- decide what gets written.
        saved = def.saved == true
    }

    Core.points[id] = point
    invalidate()
    return point
end

--- Forget a point.
--
-- Note what this does NOT do: it does not go round every character's unlock
-- list taking the id out. An unlock naming a point that no longer exists is
-- filtered on read, which is cheap and which means removing a point set
-- temporarily and putting it back does not cost anybody their exploring.
function Core.removePoint(id)
    if not Core.points[id] then
        return false
    end
    Core.points[id] = nil
    invalidate()
    return true
end

-- ---------------------------------------------------------------------------
-- Renames.
--
-- An admin's label for a point is an override, not an edit of the registered
-- point. Registration runs again on every boot, from code that says what the
-- label is, so an edit would last until the next restart. The override is
-- read at registration instead, which also means a point that registers late,
-- or a phone registered out of its own records, comes up with its new name
-- without anybody sequencing anything.
--
-- Kept in the store file (Core.saved.labels) rather than global ModData, so a
-- rename survives a wipe along with the points an admin added. This changes
-- the table and nothing else: writing the file is the caller's job, see
-- server/store.lua.
--
-- Only the label. The id is what every account's unlock list persists, so it
-- is never editable, and that is the whole reason the two are separate.
--
-- Server side in effect: the file is loaded only there. A client never needs
-- the override, because everything it draws comes out of a payload the
-- server built from the renamed point.
-- ---------------------------------------------------------------------------

local function labelStore()
    Core.saved.labels = Core.saved.labels or {}
    return Core.saved.labels
end

--- The admin's label for a point, or nil when it has none.
function Core.labelOverride(id)
    return labelStore()[id]
end

--- Put every registered point's label back in line with the overrides, after
--- the file has been read again. A rename taken out of the file goes back to
--- the registered label.
function Core.reapplyLabels()
    for id, point in pairs(Core.points) do
        point.label = Core.labelOverride(id) or point.shippedLabel
    end
    invalidate()
end

--- Rename a point.
--
-- Trimmed, and refused when longer than consts.labelMax. An empty label, or
-- one identical to the registered label, REMOVES the override rather than
-- storing it: an override that says what the registration already says does
-- nothing, reads as customised when it is stock, and would stop a later
-- version's better label from ever reaching this save.
--
-- Returns the point, or nil and a translation key saying why not.
function Core.renamePoint(id, label)
    local point = Core.points[id]
    if not point then
        return nil, "IGUI_PhunSpawn_NoSuchPoint"
    end
    if label ~= nil and type(label) ~= "string" then
        return nil, "IGUI_PhunSpawn_BadLabel"
    end
    label = label and label:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if #label > Core.consts.labelMax then
        return nil, "IGUI_PhunSpawn_LabelTooLong"
    end

    local store = labelStore()
    if label == "" or label == point.shippedLabel then
        store[id] = nil
        point.label = point.shippedLabel
    else
        store[id] = label
        point.label = label
    end
    -- The sort reads the label, and the indexes are what a reader rebuilds.
    invalidate()
    return point
end

--- Every point, WITH coordinates, for the admin editor. Never for a player:
--- this is exactly what Unlocks.payloadFor exists to withhold.
function Core.adminPayload()
    local out = {}
    for _, point in ipairs(Core.sortedPoints()) do
        table.insert(out, {
            id = point.id,
            label = point.label,
            shippedLabel = point.shippedLabel,
            renamed = point.label ~= point.shippedLabel,
            region = point.region,
            discovery = point.discovery,
            saved = point.saved,
            x = point.x,
            y = point.y,
            z = point.z
        })
    end
    return out
end

--- Rebuild the reverse indexes. Called by every reader, never by a writer.
function Core.buildIndexes()
    if Core.indexesBuilt then
        return
    end
    Core.indexesBuilt = true

    local regions = {}
    for id, point in pairs(Core.points) do
        local region = point.region or ""
        regions[region] = regions[region] or {}
        regions[region][id] = true
    end
    Core.regions = regions
end

--- Every point, sorted for a stable picker.
--
-- Sorted on (priority, label, id). The id tail is not decoration: pairs()
-- order is not stable, ties are routine, and without it one save would draw
-- the same list in two different orders.
function Core.sortedPoints()
    Core.buildIndexes()
    local out = {}
    for _, point in pairs(Core.points) do
        table.insert(out, point)
    end
    table.sort(out, function(a, b)
        if a.priority ~= b.priority then
            return a.priority < b.priority
        end
        if a.label ~= b.label then
            return a.label < b.label
        end
        return a.id < b.id
    end)
    return out
end

--- The points in one region, sorted the same way.
function Core.pointsInRegion(region)
    Core.buildIndexes()
    local ids = Core.regions[region or ""] or {}
    local out = {}
    for _, point in ipairs(Core.sortedPoints()) do
        if ids[point.id] then
            table.insert(out, point)
        end
    end
    return out
end

--- A points payload, grouped by region for the picker.
--
-- Takes the list Unlocks.payloadFor sends rather than the registry, because
-- the payload is what a client is allowed to know: an undiscovered point in it
-- has no coordinates, and grouping the registry instead would hand the picker
-- positions the server deliberately withheld.
--
-- Returns an array of
--   {name, points, known, total, bounds}
-- where `bounds` is {x1, y1, x2, y2} over the KNOWN points only, and nil when
-- the region has none. A region of nothing but undiscovered points still gets
-- a row, because "there is something in West Point" is exactly what
-- ShowUndiscovered is for; it just has nowhere to zoom to.
--
-- Sorted by name, case insensitively, with the unnamed region last. The
-- points inside each keep the payload's order, which is already the stable
-- (priority, label, id) sort.
function Core.groupByRegion(points)
    local byName, out = {}, {}
    for _, point in ipairs(points or {}) do
        local name = point.region or ""
        local group = byName[name]
        if not group then
            group = {
                name = name,
                points = {},
                known = 0,
                total = 0
            }
            byName[name] = group
            table.insert(out, group)
        end
        table.insert(group.points, point)
        group.total = group.total + 1
        if point.known and point.x and point.y then
            group.known = group.known + 1
            local b = group.bounds
            if not b then
                group.bounds = {
                    x1 = point.x,
                    y1 = point.y,
                    x2 = point.x,
                    y2 = point.y
                }
            else
                b.x1 = math.min(b.x1, point.x)
                b.y1 = math.min(b.y1, point.y)
                b.x2 = math.max(b.x2, point.x)
                b.y2 = math.max(b.y2, point.y)
            end
        end
    end
    table.sort(out, function(a, b)
        if (a.name == "") ~= (b.name == "") then
            return b.name == ""
        end
        local al, bl = a.name:lower(), b.name:lower()
        if al ~= bl then
            return al < bl
        end
        -- Names are unique keys, so this is only "West Point" against
        -- "west point", and it still has to answer the same way every time.
        return a.name < b.name
    end)
    return out
end

--- The point nearest a position, and how far away it is.
--
-- Squared distance throughout, so nothing needs a square root to answer
-- "is anything within the discovery radius". The caller compares against
-- radius * radius.
--
-- `discovery`, when given, considers only points of that kind. The discovery
-- sweep needs it: without it a pay phone standing nearer than an explore point
-- would be "the nearest", fail the explore test, and hide the explore point
-- behind it for as long as the player stood there.
function Core.nearestPoint(x, y, z, discovery)
    Core.buildIndexes()
    local best, bestDistance
    for _, point in pairs(Core.points) do
        if (point.z or 0) == (z or 0) and (not discovery or point.discovery == discovery) then
            local dx, dy = point.x - x, point.y - y
            local distance = (dx * dx) + (dy * dy)
            if not bestDistance or distance < bestDistance then
                best, bestDistance = point, distance
            end
        end
    end
    return best, bestDistance
end

--- Counts, for the boot log. Always true, unlike anything about what is
--- missing, which is why this is all that is logged at boot.
function Core.describeRegistry()
    Core.buildIndexes()
    local points, regions = 0, 0
    for _ in pairs(Core.points) do
        points = points + 1
    end
    for _ in pairs(Core.regions) do
        regions = regions + 1
    end
    return tostring(points) .. " point(s) across " .. tostring(regions) .. " region(s)"
end

return Core
