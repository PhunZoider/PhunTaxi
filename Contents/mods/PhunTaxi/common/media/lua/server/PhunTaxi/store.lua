if isClient() then
    return
end
require "PhunTaxi/points"
require "PhunTaxi/phones"
local Core = PhunTaxi
-- PhunInteriors' copy, which is PhunMart2's. PhunInteriors is a hard
-- dependency, so this is a require rather than a third vendored copy.
local json = require "PhunInteriors/json"
local Store = {}
Core.modules.store = Store

-- ---------------------------------------------------------------------------
-- The store file: what an admin set up, kept outside the save.
--
-- PhunTaxi.json, in the game's Lua folder beside PhunInteriors.json. That
-- folder is not part of the world, so a wipe leaves it alone, and that is the
-- whole reason for it: an admin walks the map adding points and keeping pay
-- phones once, and the next world starts with them. Global ModData is in the
-- save and goes with it.
--
-- One flat list, `entries`, since a point and a phone never share a square
-- and a hand edit should not have to know which of four tables a thing
-- lives in. Every entry is one of three:
--
--   a phone  {x, y, z, facing, label?, kept?}
--           The default: no `type`, or "phone". A pay phone kept across
--           wipes. `x, y, z` is where the traveller STANDS, as for a point,
--           and `facing` (E, S, W or N) puts the phone on the square behind
--           and picks its sprite. When that square first loads in a new
--           world, one of ours is put there. See phone_swap.lua. It takes no
--           id: its point id is built from the phone's square, because that
--           is the id every account that used it has in its list. `label`
--           renames that point. `kept: false` releases a shipped phone (see
--           below): Release writes it, and taking the line out keeps the
--           phone again.
--   a point  {type = "point", id?, label?, x, y, z, facing?, region?,
--            discovery?, priority?, deleted?}
--           `x, y, z` is where the character wakes up, and `facing` asks
--           for a phone behind it, exactly as for a phone. `id` defaults to
--           Store.customId of the square, which is what one added in game
--           gets, and `label` to the square's coordinates. `discovery` is
--           start, explore (the default) or granted; nothing else can ever
--           be unlocked without a thing on the map to build or use. Any id
--           is accepted, so a point of the same id as a shipped one
--           replaces it, which is how a placeholder's square gets fixed
--           without code.
--   an override  {id, label?, deleted?}
--           No square: it changes a point this file does not define, a
--           shipped one, a third party's, or a phone nobody kept. `label`
--           renames it; `deleted` tombstones it, so it registers into
--           Core.deleted instead of the registry. Taking the line out puts
--           it back. See Core.deletePoint.
--
-- In memory it is still views, Core.saved.{points, phones, labels, deleted,
-- released}, which is what the registry and phone_swap read: the list is
-- only the file's shape, taken apart by sanitise and put back by document. A
-- rename of a point the file defines is written into its own entry, so it
-- has one label and not two, and so it cannot be reset to what it was.
--
-- Under the file sit the SHIPPED phones, Core.shipped (defaults.lua), a list
-- in this same shape, as PhunZones puts its own zones under an admin's. They
-- are merged into Core.saved.phones at load, so everything that reads the
-- kept phones sees them without knowing where they came from, and the file
-- holds only the difference: a shipped phone kept as shipped is not written,
-- one with its facing changed is written whole and wins, and one released is
-- written as `kept: false`. A shipped label is not an override but the
-- phone's registered label (Store.shippedLabel), so Reset name goes back to
-- it, and a later version's better label reaches every world that has not
-- renamed the phone. A shipped entry with `mods` counts only when one of
-- those mods is active, as for a point.
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
-- with PhunTaxi.admin("reload").
-- ---------------------------------------------------------------------------

Store.FILE = Core.consts.storeFile
Store.VERSION = 2

-- Core.shipped, checked, by Store.readShipped: {phones, labels}.
Store.shipped = {
    phones = {},
    labels = {}
}

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
        return nil, "IGUI_PhunTaxi_BadLabel"
    end
    label = label:gsub("^%s+", ""):gsub("%s+$", "")
    if label == "" then
        return nil, "IGUI_PhunTaxi_BadLabel"
    end
    if #label > Core.consts.labelMax then
        return nil, "IGUI_PhunTaxi_LabelTooLong"
    end
    return label
end

local function whole(value)
    if type(value) ~= "number" then
        return nil
    end
    return math.floor(value)
end

--- The label a point with none is given: its square.
function Store.defaultLabel(x, y)
    return tostring(x) .. ", " .. tostring(y)
end

--- A decoded file, checked. Returns clean {points, phones, labels, deleted}
--- and a list of complaints. Never throws: an entry that is wrong is left
--- out and said so, and the rest of the file still counts. Of two entries
--- for one thing, the later wins, and that is said too.
---
--- A third return of true means the file is refused whole, because reading
--- it as empty would let the next change made in game write over it: the
--- four table shape of version 1, or an `entries` that is an object.
function Store.sanitise(doc)
    local out = {
        points = {},
        phones = {},
        labels = {},
        deleted = {},
        released = {}
    }
    local problems = {}
    local function complain(text)
        table.insert(problems, text)
    end
    if type(doc) ~= "table" then
        complain("the file is not a JSON object")
        return out, problems
    end
    if doc.entries == nil and (doc.points ~= nil or doc.phones ~= nil or doc.labels ~= nil or doc.deleted ~= nil) then
        complain("the file is in the old shape (points, phones, labels, deleted); write it as one entries list")
        return out, problems, true
    end
    local list = doc.entries
    if list == nil then
        return out, problems
    end
    if type(list) ~= "table" then
        complain("entries is not a list")
        return out, problems, true
    end
    for k in pairs(list) do
        if type(k) ~= "number" then
            complain("entries is not a list")
            return out, problems, true
        end
    end

    -- A string, nil for none, or false for one that is wrong and said so.
    local function labelOf(where, entry)
        if entry.label == nil then
            return nil
        end
        local clean, why = Store.cleanLabel(entry.label)
        if not clean then
            complain(where .. (why == "IGUI_PhunTaxi_LabelTooLong" and " has a label that is too long" or
                         " has a label that is not usable"))
            return false
        end
        return clean
    end

    local function readPhone(where, entry, x, y, z)
        if not FACINGS[entry.facing] then
            complain(where .. " has facing '" .. tostring(entry.facing) .. "'; it must be E, S, W or N")
            return
        end
        local label = labelOf(where, entry)
        if label == false then
            return
        end
        if entry.id ~= nil then
            complain(where .. " is a phone, which is known by its square, so its id is ignored")
        end
        if entry.deleted then
            -- Kept all the same. Taking the entry out is how a phone stops
            -- being kept, and a flag that half says so is not.
            complain(where .. " is a phone, which is released rather than deleted: take the entry out")
        end
        if entry.kept ~= nil and type(entry.kept) ~= "boolean" then
            complain(where .. " has kept '" .. tostring(entry.kept) .. "'; it must be true or false")
            return
        end
        -- The file says where the traveller stands, and the phone is behind.
        -- Keyed by the phone's square, since that is what its point id is
        -- built from.
        local px, py = Core.phoneBehind(x, y, entry.facing)
        local key = Store.keyOf(px, py, z)
        if out.phones[key] or out.released[key] then
            complain("two phones on " .. key .. "; the later one is used")
        end
        local phone = {
            x = px,
            y = py,
            z = z,
            facing = entry.facing
        }
        if entry.kept == false then
            out.phones[key], out.released[key] = nil, phone
        else
            out.phones[key], out.released[key] = phone, nil
        end
        out.labels[Core.phonePointId(px, py, z)] = label or nil
    end

    local function readPoint(where, entry, x, y, z)
        local id = entry.id
        if id == nil then
            id = Store.customId(x, y, z)
        elseif type(id) ~= "string" or id == "" then
            complain(where .. " has an id that is not a string")
            return
        end
        local label = labelOf(where, entry)
        if label == false then
            return
        end
        local discovery = entry.discovery or Core.discovery.explore
        if not KINDS[discovery] then
            -- Left out rather than read as explore. A point the admin meant
            -- as a start point and typed wrong would otherwise quietly become
            -- one nobody starts with.
            complain(where .. " has discovery '" .. tostring(discovery) .. "'; it must be start, explore or granted")
            return
        end
        if entry.facing ~= nil and not FACINGS[entry.facing] then
            -- Left out for the same reason: a point meant to have a phone
            -- is a taxi stop, and one quietly without it is not.
            complain(where .. " has facing '" .. tostring(entry.facing) .. "'; it must be E, S, W or N")
            return
        end
        if out.points[id] then
            complain("two points with the id " .. id .. "; the later one is used")
        end
        out.points[id] = {
            label = label or Store.defaultLabel(x, y),
            x = x,
            y = y,
            z = z,
            region = type(entry.region) == "string" and entry.region ~= "" and entry.region or nil,
            discovery = discovery,
            priority = type(entry.priority) == "number" and entry.priority or nil,
            phone = entry.facing
        }
        out.deleted[id] = entry.deleted == true or nil
    end

    -- After every definition, so an override of a point the file defines
    -- lands on it wherever the two are in the list.
    local function readOverride(where, entry)
        local id = entry.id
        local label = labelOf(where, entry)
        if label == false then
            return
        end
        if label == nil and entry.deleted == nil then
            complain(where .. " has no square, label or deleted, so it does nothing")
            return
        end
        if label and out.points[id] then
            -- A point the file defines has one label, its own.
            out.points[id].label = label
        elseif label then
            out.labels[id] = label
        end
        -- `false` is somebody undoing a tombstone by hand, which is what
        -- taking the line out does, so it is quiet.
        if entry.deleted ~= nil then
            out.deleted[id] = entry.deleted or nil
        end
    end

    local overrides = {}
    for n, entry in ipairs(list) do
        if type(entry) ~= "table" then
            complain("entry " .. n .. " is not an object")
        else
            local x, y, z = whole(entry.x), whole(entry.y), whole(entry.z) or 0
            local where = type(entry.id) == "string" and entry.id ~= "" and entry.id or
                              (x and y and ("the entry at " .. Store.keyOf(x, y, z))) or ("entry " .. n)
            local kind = entry.type or "phone"
            if entry.deleted ~= nil and type(entry.deleted) ~= "boolean" then
                complain(where .. " has deleted '" .. tostring(entry.deleted) .. "'; it must be true or false")
            elseif entry.x == nil and entry.y == nil then
                if type(entry.id) ~= "string" or entry.id == "" then
                    complain(where .. " has no square and no id, so it says nothing")
                else
                    table.insert(overrides, {
                        where = where,
                        entry = entry
                    })
                end
            elseif not x or not y then
                complain(where .. " needs a number for both x and y")
            elseif kind == "phone" then
                readPhone(where, entry, x, y, z)
            elseif kind == "point" then
                readPoint(where, entry, x, y, z)
            else
                complain(where .. " has type '" .. tostring(entry.type) .. "'; it must be point or phone")
            end
        end
    end
    for _, o in ipairs(overrides) do
        readOverride(o.where, o.entry)
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

local function empty()
    return {
        points = {},
        phones = {},
        labels = {},
        deleted = {},
        released = {}
    }
end

--- Core.shipped, checked the way the file is, into Store.shipped: {phones,
--- labels}. An entry whose `mods` has none active is left out quietly, since
--- that is what `mods` is for. A point or a tombstone is refused: a shipped
--- point is registered in code, with Core.registerPoint.
--- @return a list of complaints
function Store.readShipped()
    local list, problems = {}, {}
    for n, entry in ipairs(Core.shipped) do
        local mods = type(entry) == "table" and entry.mods or nil
        local ok, why = Core.tools.checkMods(mods)
        if not ok then
            table.insert(problems, "entry " .. n .. ": " .. why)
        elseif type(entry) == "table" and (entry.type == "point" or entry.deleted ~= nil) then
            table.insert(problems, "entry " .. n .. " is a point or a tombstone; register a point in code instead")
        elseif Core.tools.anyModActive(mods) then
            table.insert(list, entry)
        end
    end
    local clean, more = Store.sanitise({
        entries = list
    })
    for _, complaint in ipairs(more) do
        table.insert(problems, complaint)
    end
    Store.shipped = {
        phones = clean.phones,
        labels = clean.labels
    }
    return problems
end

--- The shipped label for a phone's point id, or nil. What registerRecord
--- registers the phone as, under any rename in the file.
function Store.shippedLabel(id)
    return Store.shipped.labels[id]
end

--- The shipped phones under Core.saved.phones. One the file has on its
--- square, kept or released, is the file's.
local function mergeShipped()
    local saved = Core.saved
    for key, phone in pairs(Store.shipped.phones) do
        if not saved.phones[key] and not saved.released[key] then
            saved.phones[key] = {
                x = phone.x,
                y = phone.y,
                z = phone.z,
                facing = phone.facing
            }
        end
    end
end

--- Read the file into Core.saved, over the shipped phones. Registers
--- nothing: see registerAll.
---
--- Never throws and never refuses to boot. A file that cannot be parsed is
--- reported and treated as empty, and it is NOT written over until an admin
--- changes something, so a stray comma costs a restart rather than the file.
--- The shipped phones are kept either way.
--- @return a list of complaints
function Store.load()
    Core.saved = empty()
    Store.unreadable = false
    local problems = Store.readShipped()
    for _, complaint in ipairs(problems) do
        Core.logLn("shipped phones: " .. complaint)
    end

    local text = readAll(Store.FILE)
    if not text or text == "" then
        Core.debugLn("no " .. Store.FILE .. "; nothing saved yet")
        mergeShipped()
        return problems
    end

    local doc, err = json.decode(text)
    if err then
        Store.unreadable = true
        Core.logLn("could not read " .. Store.FILE .. ": " .. tostring(err))
        Core.logLn("nothing saved is being used, and the file will not be written until it reads again")
        mergeShipped()
        table.insert(problems, tostring(err))
        return problems
    end

    local clean, more, refused = Store.sanitise(doc)
    for _, complaint in ipairs(more) do
        Core.logLn(Store.FILE .. ": " .. complaint)
        table.insert(problems, complaint)
    end
    if refused then
        Store.unreadable = true
        Core.logLn("nothing saved is being used, and the file will not be written until it reads again")
        mergeShipped()
        return problems
    end
    Core.saved = clean
    local own = count(clean.phones)
    mergeShipped()
    Core.logLn(string.format("%s: %d point(s), %d phone(s), %d shipped phone(s), %d released, %d rename(s), %d deleted%s",
        Store.FILE, count(clean.points), own, count(clean.phones) - own, count(clean.released), count(clean.labels),
        count(clean.deleted), #more > 0 and (", " .. #more .. " ignored") or ""))
    return problems
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do
        table.insert(keys, k)
    end
    table.sort(keys)
    return keys
end

--- The file as it should be written: Core.saved put back together as one
--- list. Phones, then points, then overrides, each sorted, so a save that
--- changed one thing is a diff of one entry. What a field defaults to is left
--- out, which is what keeps an added point to a square and a label.
function Store.document()
    local saved = Core.saved
    local entries = {}
    -- What an entry has already carried, so it is not written again as an
    -- override. A phone carries its rename, never a tombstone.
    local labelled, tombstoned = {}, {}

    local function phoneEntry(phone, kept)
        local z = phone.z or 0
        local id = Core.phonePointId(phone.x, phone.y, z)
        local x, y = Core.phoneFront(phone.x, phone.y, phone.facing)
        labelled[id] = true
        table.insert(entries, {
            x = x,
            y = y,
            z = z,
            facing = phone.facing,
            label = saved.labels[id],
            kept = kept
        })
    end

    -- A phone kept as it was shipped is not written, so the file holds only
    -- what differs from defaults.lua. Its rename, if any, goes out below as
    -- an override.
    local shipped = Store.shipped.phones
    for _, key in ipairs(sortedKeys(saved.phones)) do
        local phone = saved.phones[key]
        if not (shipped[key] and shipped[key].facing == phone.facing) then
            phoneEntry(phone, nil)
        end
    end
    -- Written even for a phone not shipped this time, such as one whose
    -- `mods` is not active: the release still holds when it is again.
    for _, key in ipairs(sortedKeys(saved.released)) do
        if not saved.phones[key] then
            phoneEntry(saved.released[key], false)
        end
    end

    for _, id in ipairs(sortedKeys(saved.points)) do
        local def = saved.points[id]
        local z = def.z or 0
        local label = saved.labels[id] or def.label
        labelled[id], tombstoned[id] = true, true
        table.insert(entries, {
            type = "point",
            id = id ~= Store.customId(def.x, def.y, z) and id or nil,
            label = label ~= Store.defaultLabel(def.x, def.y) and label or nil,
            x = def.x,
            y = def.y,
            z = z,
            facing = def.phone,
            region = def.region,
            discovery = def.discovery ~= Core.discovery.explore and def.discovery or nil,
            priority = def.priority,
            deleted = saved.deleted[id] or nil
        })
    end

    local rest = {}
    for id in pairs(saved.labels) do
        if not labelled[id] then
            rest[id] = true
        end
    end
    for id in pairs(saved.deleted) do
        if not tombstoned[id] then
            rest[id] = true
        end
    end
    for _, id in ipairs(sortedKeys(rest)) do
        table.insert(entries, {
            id = id,
            label = not labelled[id] and saved.labels[id] or nil,
            deleted = saved.deleted[id] or nil
        })
    end

    return {
        version = Store.VERSION,
        entries = entries
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
        phone = def.phone,
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
        return nil, "IGUI_PhunTaxi_NoSuchPoint"
    end
    local clean, why = Store.cleanLabel(label)
    if not clean then
        return nil, why
    end
    local id = Store.customId(x, y, z)
    if Core.saved.points[id] then
        return nil, "IGUI_PhunTaxi_PointHere"
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
        return nil, "IGUI_PhunTaxi_NotSaved"
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
        return nil, "IGUI_PhunTaxi_NotSavedPoint"
    end
    local label, tombstone = Core.saved.labels[id], Core.saved.deleted[id]
    Core.saved.points[id] = nil
    Core.saved.labels[id] = nil
    Core.saved.deleted[id] = nil
    if not commit(function()
        Core.saved.points[id] = def
        Core.saved.labels[id] = label
        Core.saved.deleted[id] = tombstone
    end) then
        return nil, "IGUI_PhunTaxi_NotSaved"
    end
    Core.removePoint(id)
    return true
end

--- Tombstone a point and save it. Core.deletePoint's rules and returns, plus
--- IGUI_PhunTaxi_NotSaved when the file would not write, in which case the
--- point is put back.
function Store.deletePoint(id)
    local point, why = Core.deletePoint(id)
    if not point then
        return nil, why
    end
    -- The undo sets the tombstone back directly rather than through
    -- Core.restorePoint or Core.deletePoint, whose refusals are for an
    -- admin's request and not for putting things as they were.
    if not commit(function()
        Core.saved.deleted[id] = nil
        Core.reapplyTombstones()
    end) then
        return nil, "IGUI_PhunTaxi_NotSaved"
    end
    return point
end

--- Take a tombstone off and save it.
function Store.restorePoint(id)
    local point, why = Core.restorePoint(id)
    if not point then
        return nil, why
    end
    if not commit(function()
        Core.saved.deleted[id] = true
        Core.reapplyTombstones()
    end) then
        return nil, "IGUI_PhunTaxi_NotSaved"
    end
    return point
end

--- "Take this point out", whatever it is. A point an admin added on a
--- square goes from the file for good, since nothing else would register it
--- again and a tombstone would only be left behind to catch the next point
--- added there. Anything else is tombstoned: shipped points, a third
--- party's, and a file entry standing in for one of those, which Restore
--- brings back as it was.
--- @return the point, or nil and a translation key; and whether it was a
---         tombstone
function Store.takeOut(id)
    local point = Core.points[id]
    local custom = type(id) == "string" and id:sub(1, #Core.consts.customPrefix) == Core.consts.customPrefix
    if point and custom and Core.saved.points[id] then
        -- Core.deletePoint's rule, which removing from the file would
        -- otherwise walk round.
        if Core.isLastStart(id) then
            return nil, "IGUI_PhunTaxi_LastStart"
        end
        local ok, why = Store.removePoint(id)
        if not ok then
            return nil, why
        end
        return point, false
    end
    local deleted, why = Store.deletePoint(id)
    if not deleted then
        return nil, why
    end
    return deleted, true
end

--- Change how a point in the file is found.
function Store.setKind(id, discovery)
    local def = Core.saved.points[id]
    if not def then
        return nil, "IGUI_PhunTaxi_NotSavedPoint"
    end
    if not KINDS[discovery] then
        return nil, "IGUI_PhunTaxi_BadKind"
    end
    local was = def.discovery
    def.discovery = discovery
    if not commit(function()
        def.discovery = was
    end) then
        return nil, "IGUI_PhunTaxi_NotSaved"
    end
    return register(id, def)
end

--- Keep a phone. `record` is a swap record; only where it is and which way
--- it faces are written, since region and label are worked out again in
--- whatever world it lands in.
function Store.keepPhone(key, record)
    local saved = Core.saved
    local was, wasReleased = saved.phones[key], saved.released[key]
    saved.phones[key] = {
        x = record.x,
        y = record.y,
        z = record.z or 0,
        facing = record.facing
    }
    saved.released[key] = nil
    return commit(function()
        saved.phones[key] = was
        saved.released[key] = wasReleased
    end)
end

--- A shipped phone is released by saying so in the file, since taking its
--- line out cannot stop defaults.lua keeping it.
function Store.releasePhone(key)
    local saved = Core.saved
    local was = saved.phones[key]
    if not was then
        return false
    end
    saved.phones[key] = nil
    saved.released[key] = Store.shipped.phones[key] and was or nil
    return commit(function()
        saved.phones[key] = was
        saved.released[key] = nil
    end)
end

--- Rename a point and save it. Core.renamePoint's rules and returns, plus
--- IGUI_PhunTaxi_NotSaved when the file would not write, in which case the
--- old name is put back.
---
--- A point the file defines is renamed in its own entry rather than by an
--- override, so its entry has one label: what it is called becomes what it
--- is registered as, and there is nothing left for Reset name to go back to.
function Store.rename(id, label)
    local was = Core.saved.labels[id]
    local def = Core.saved.points[id]
    local defWas = def and def.label
    local point, why = Core.renamePoint(id, label)
    if not point then
        return nil, why
    end
    if def then
        def.label = point.label
        point.shippedLabel = point.label
        Core.saved.labels[id] = nil
    end
    if not commit(function()
        Core.saved.labels[id] = was
        if def then
            def.label = defWas
            point.shippedLabel = defWas
        end
        point.label = was or point.shippedLabel
    end) then
        return nil, "IGUI_PhunTaxi_NotSaved"
    end
    return point
end

--- Read the file again, for a hand edit made while the server runs.
---
--- Points from the old read are taken out and the new ones registered, and
--- every tombstone and label is put back in line. Phones are phone_swap's to
--- adopt; the caller does that after.
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
    Core.reapplyTombstones()
    Core.reapplyLabels()
    return problems
end

return Store
