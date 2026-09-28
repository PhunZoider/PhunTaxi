if isClient() then
    return
end
require "PhunSpawn/points"
require "PhunSpawn/phones"
local Core = PhunSpawn
-- PhunInteriors' copy, which is PhunMart2's. PhunInteriors is a hard
-- dependency, so this is a require rather than a third vendored copy.
local json = require "PhunInteriors/json"
local Store = {}
Core.modules.store = Store

-- ---------------------------------------------------------------------------
-- The store file: what an admin set up, kept outside the save.
--
-- PhunSpawn.json, in the game's Lua folder beside PhunInteriors.json. That
-- folder is not part of the world, so a wipe leaves it alone, and that is the
-- whole reason for it: an admin walks the map adding points and keeping pay
-- phones once, and the next world starts with them. Global ModData is in the
-- save and goes with it.
--
-- Three things, each keyed so a hand edit is one line to find:
--
--   points  id -> {label, x, y, z, region, discovery, priority}
--           Points an admin added. `x, y, z` is where the character wakes
--           up. `discovery` is start, explore or granted; nothing else can
--           ever be unlocked without a thing on the map to build or use.
--           Any id is accepted, so a point of the same id as a shipped one
--           replaces it, which is how a placeholder's square gets fixed
--           without code.
--   phones  "x_y_z" -> {x, y, z, facing, sprite}
--           Pay phones kept across wipes. `x, y, z` is the PHONE's square,
--           as in a swap record, and `facing` is E, S, W or N, which puts
--           the point on the square in front. When the square first loads
--           in a new world, one of ours is put there. See phone_swap.lua.
--   labels  id -> label
--           Renames, of any point, shipped or not.
--
-- SERVER SIDE ONLY: getFileReader resolves against the Lua folder of the
-- machine running it, so a client would read its own. The rules for the two
-- file calls are PhunInteriors' and were paid for there: `false` to
-- getFileReader so a missing file stays missing, and encode BEFORE
-- getFileWriter, because it truncates on open.
--
-- Written on every change an admin makes in game, so there is no Save button
-- to forget. The flip side: a hand edit made while the server runs is
-- overwritten by the next change made in game, unless it is read in first
-- with PhunSpawn.admin("reload").
-- ---------------------------------------------------------------------------

Store.FILE = Core.consts.storeFile
Store.VERSION = 1

-- What a point in the file may be found by.
local KINDS = {
    [Core.discovery.start] = true,
    [Core.discovery.explore] = true,
    [Core.discovery.granted] = true
}
Store.KINDS = KINDS

local FACINGS = {
    E = true,
    S = true,
    W = true,
    N = true
}

function Store.keyOf(x, y, z)
    return tostring(x) .. "_" .. tostring(y) .. "_" .. tostring(z or 0)
end

function Store.customId(x, y, z)
    return Core.consts.customPrefix .. Store.keyOf(x, y, z)
end

--- Trimmed, or nil and a translation key saying why not. The rename rules,
--- so a label cannot get into the file by one door that the other refuses.
function Store.cleanLabel(label)
    if type(label) ~= "string" then
        return nil, "IGUI_PhunSpawn_BadLabel"
    end
    label = label:gsub("^%s+", ""):gsub("%s+$", "")
    if label == "" then
        return nil, "IGUI_PhunSpawn_BadLabel"
    end
    if #label > Core.consts.labelMax then
        return nil, "IGUI_PhunSpawn_LabelTooLong"
    end
    return label
end

local function whole(value)
    if type(value) ~= "number" then
        return nil
    end
    return math.floor(value)
end

--- A decoded file, checked. Returns clean {points, phones, labels} and a
--- list of complaints. Never throws: an entry that is wrong is left out and
--- said so, and the rest of the file still counts.
function Store.sanitise(doc)
    local out = {
        points = {},
        phones = {},
        labels = {}
    }
    local problems = {}
    if type(doc) ~= "table" then
        table.insert(problems, "the file is not a JSON object")
        return out, problems
    end

    for id, def in pairs(type(doc.points) == "table" and doc.points or {}) do
        local x, y = whole(type(def) == "table" and def.x), whole(type(def) == "table" and def.y)
        local label = type(def) == "table" and Store.cleanLabel(def.label)
        local discovery = type(def) == "table" and def.discovery or Core.discovery.explore
        if type(id) ~= "string" or id == "" then
            table.insert(problems, "a point with no id")
        elseif not x or not y then
            table.insert(problems, "point " .. id .. " has no x and y")
        elseif not label then
            table.insert(problems, "point " .. id .. " has no usable label")
        elseif not KINDS[discovery] then
            -- Left out rather than read as explore. A point the admin meant
            -- as a start point and typed wrong would otherwise quietly become
            -- one nobody starts with.
            table.insert(problems, "point " .. id .. " has discovery '" .. tostring(discovery) ..
                "'; it must be start, explore or granted")
        else
            out.points[id] = {
                label = label,
                x = x,
                y = y,
                z = whole(def.z) or 0,
                region = type(def.region) == "string" and def.region ~= "" and def.region or nil,
                discovery = discovery,
                priority = type(def.priority) == "number" and def.priority or nil
            }
        end
    end

    for key, def in pairs(type(doc.phones) == "table" and doc.phones or {}) do
        local x, y = whole(type(def) == "table" and def.x), whole(type(def) == "table" and def.y)
        local facing = type(def) == "table" and def.facing
        if not x or not y then
            table.insert(problems, "phone " .. tostring(key) .. " has no x and y")
        elseif not FACINGS[facing] then
            table.insert(problems, "phone " .. tostring(key) .. " has facing '" .. tostring(facing) ..
                "'; it must be E, S, W or N")
        else
            local z = whole(def.z) or 0
            -- Keyed by its own square whatever the file called it, since the
            -- key is what the phone's point id is built from.
            out.phones[Store.keyOf(x, y, z)] = {
                x = x,
                y = y,
                z = z,
                facing = facing,
                sprite = type(def.sprite) == "string" and def.sprite or nil
            }
        end
    end

    for id, label in pairs(type(doc.labels) == "table" and doc.labels or {}) do
        local clean = Store.cleanLabel(label)
        if type(id) ~= "string" or not clean then
            table.insert(problems, "the rename of " .. tostring(id) .. " is not a usable label")
        else
            out.labels[id] = clean
        end
    end

    return out, problems
end

--- Whole file as one string, or nil when it is not there.
local function readAll(filename)
    local reader = getFileReader(filename, false)
    if not reader then
        return nil
    end
    local lines = {}
    local line = reader:readLine()
    while line do
        lines[#lines + 1] = line
        line = reader:readLine()
    end
    reader:close()
    return table.concat(lines, "\n")
end

local function count(t)
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end

--- Read the file into Core.saved. Registers nothing: see registerAll.
---
--- Never throws and never refuses to boot. A file that cannot be parsed is
--- reported and treated as empty, and it is NOT written over until an admin
--- changes something, so a stray comma costs a restart rather than the file.
--- @return a list of complaints
function Store.load()
    Core.saved = {
        points = {},
        phones = {},
        labels = {}
    }
    Store.unreadable = false
    local text = readAll(Store.FILE)
    if not text or text == "" then
        Core.debugLn("no " .. Store.FILE .. "; nothing saved yet")
        return {}
    end

    local doc, err = json.decode(text)
    if err then
        Store.unreadable = true
        Core.logLn("could not read " .. Store.FILE .. ": " .. tostring(err))
        Core.logLn("nothing saved is being used, and the file will not be written until it reads again")
        return {tostring(err)}
    end

    local clean, problems = Store.sanitise(doc)
    Core.saved = clean
    for _, complaint in ipairs(problems) do
        Core.logLn(Store.FILE .. ": " .. complaint)
    end
    Core.logLn(string.format("%s: %d point(s), %d phone(s), %d rename(s)%s", Store.FILE, count(clean.points),
        count(clean.phones), count(clean.labels), #problems > 0 and (", " .. #problems .. " ignored") or ""))
    return problems
end

--- The file as it should be written.
function Store.document()
    return {
        version = Store.VERSION,
        points = Core.saved.points,
        phones = Core.saved.phones,
        labels = Core.saved.labels
    }
end

--- Write Core.saved out. Returns true, or false and why not.
function Store.save()
    -- A file that did not parse is somebody's hand edit with a typo in it.
    -- Writing now would replace all of it with the little that was added
    -- since boot.
    if Store.unreadable then
        Core.logLn("not writing " .. Store.FILE .. ": it did not read at boot. Fix it and reload.")
        return false, "unreadable"
    end
    -- Encoded before the file is opened: getFileWriter truncates on open.
    local text, err = json.encodePretty(Store.document())
    if not text then
        Core.logLn("refusing to save " .. Store.FILE .. ": " .. tostring(err))
        return false, tostring(err)
    end
    local writer = getFileWriter(Store.FILE, true, false)
    if not writer then
        return false, "could not open " .. Store.FILE .. " for writing"
    end
    writer:write(text)
    writer:close()
    Core.debugLn("wrote " .. Store.FILE)
    return true
end

--- Save, or put the change back. `undo` restores what the change replaced,
--- so the file and the registry never disagree about what is saved.
local function commit(undo)
    local ok = Store.save()
    if not ok then
        undo()
        return false
    end
    return true
end

local function register(id, def)
    return Core.registerPoint(id, {
        label = def.label,
        x = def.x,
        y = def.y,
        z = def.z,
        region = def.region,
        discovery = def.discovery,
        priority = def.priority,
        saved = true
    })
end

--- Register every point in the file. After the code's own points, so a
--- point in the file replaces a shipped one of the same id.
function Store.registerAll()
    local n = 0
    for id, def in pairs(Core.saved.points) do
        if register(id, def) then
            n = n + 1
        end
    end
    return n
end

--- Add a point on a square. Returns the point, or nil and a translation key.
function Store.addPoint(x, y, z, label, region)
    x, y, z = whole(x), whole(y), whole(z) or 0
    if not x or not y then
        return nil, "IGUI_PhunSpawn_NoSuchPoint"
    end
    local clean, why = Store.cleanLabel(label)
    if not clean then
        return nil, why
    end
    local id = Store.customId(x, y, z)
    if Core.saved.points[id] then
        return nil, "IGUI_PhunSpawn_PointHere"
    end
    local def = {
        label = clean,
        x = x,
        y = y,
        z = z,
        region = region,
        discovery = Core.discovery.explore
    }
    Core.saved.points[id] = def
    if not commit(function()
        Core.saved.points[id] = nil
    end) then
        return nil, "IGUI_PhunSpawn_NotSaved"
    end
    return register(id, def)
end

--- Take a point out of the file and the registry. Its rename goes with it.
---
--- A point in the file that replaced a shipped one is gone until the next
--- boot, when the shipped one registers again.
function Store.removePoint(id)
    local def = Core.saved.points[id]
    if not def then
        return nil, "IGUI_PhunSpawn_NotSavedPoint"
    end
    local label = Core.saved.labels[id]
    Core.saved.points[id] = nil
    Core.saved.labels[id] = nil
    if not commit(function()
        Core.saved.points[id] = def
        Core.saved.labels[id] = label
    end) then
        return nil, "IGUI_PhunSpawn_NotSaved"
    end
    Core.removePoint(id)
    return true
end

--- Change how a point in the file is found.
function Store.setKind(id, discovery)
    local def = Core.saved.points[id]
    if not def then
        return nil, "IGUI_PhunSpawn_NotSavedPoint"
    end
    if not KINDS[discovery] then
        return nil, "IGUI_PhunSpawn_BadKind"
    end
    local was = def.discovery
    def.discovery = discovery
    if not commit(function()
        def.discovery = was
    end) then
        return nil, "IGUI_PhunSpawn_NotSaved"
    end
    return register(id, def)
end

--- Keep a phone. `record` is a swap record; only where it is and which way
--- it faces are written, since region and label are worked out again in
--- whatever world it lands in.
function Store.keepPhone(key, record)
    local was = Core.saved.phones[key]
    Core.saved.phones[key] = {
        x = record.x,
        y = record.y,
        z = record.z or 0,
        facing = record.facing,
        sprite = record.sprite
    }
    return commit(function()
        Core.saved.phones[key] = was
    end)
end

function Store.releasePhone(key)
    local was = Core.saved.phones[key]
    if not was then
        return false
    end
    Core.saved.phones[key] = nil
    return commit(function()
        Core.saved.phones[key] = was
    end)
end

--- Rename a point and save it. Core.renamePoint's rules and returns, plus
--- IGUI_PhunSpawn_NotSaved when the file would not write, in which case the
--- old name is put back.
function Store.rename(id, label)
    local was = Core.saved.labels[id]
    local point, why = Core.renamePoint(id, label)
    if not point then
        return nil, why
    end
    if not commit(function()
        Core.saved.labels[id] = was
        point.label = was or point.shippedLabel
    end) then
        return nil, "IGUI_PhunSpawn_NotSaved"
    end
    return point
end

--- Read the file again, for a hand edit made while the server runs.
---
--- Points from the old read are taken out and the new ones registered, and
--- every label is put back in line. Phones are phone_swap's to adopt; the
--- caller does that after.
--- @return a list of complaints
function Store.reload()
    local previous = Core.saved
    for id in pairs(previous.points) do
        Core.removePoint(id)
    end
    local problems = Store.load()
    -- A hand edit with a typo in it. Carry on with what was read last, and
    -- leave the file unwritable until it reads, so nothing made in game
    -- replaces the edit before somebody fixes it.
    if Store.unreadable then
        Core.saved = previous
    end
    Store.registerAll()
    Core.reapplyLabels()
    return problems
end

return Store
