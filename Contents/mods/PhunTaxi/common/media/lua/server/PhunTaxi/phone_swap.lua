if isClient() then
    return
end
require "PhunTaxi/points"
require "PhunTaxi/phones"
local Core = PhunTaxi
local Unlocks = require "PhunTaxi/unlocks"
local Store = require "PhunTaxi/store"
local PhoneSwap = {}

-- ---------------------------------------------------------------------------
-- Swapping vanilla pay phones for ours, and making each one a spawn point.
--
-- Every square a phone may go on is known before any of them loads: the
-- phones the maps put down (map_phones.lua, read out of the lotpacks by
-- scripts/phones.pl) and the spots with no phone at all (defaults.lua,
-- candidates.lua). Together they are the POOL, and which of them get one of
-- ours is decided for the whole world at once (resolve), not square by
-- square as they load. So LoadGridsquare looks at a square only if the pool
-- or a record names it, and every other square, nearly all of them, costs a
-- table lookup.
--
-- A map phone goes up at PhoneChance percent and a spot at its own chance,
-- and either only if no phone already taken or standing is within
-- PhoneDistance, which is what stops one street having three. A PhunZones
-- zone may set its own of both (`phoneChance`, `phoneDistance`, see chanceAt
-- and spacingAt), so an admin can crowd a city with phones and leave the
-- countryside sparse.
--
-- A swapped phone is recorded in global ModData under its square, and every
-- record registers a point at the square in FRONT of the phone, since the
-- phone's own square is solid. Discovery is `used`: walking past does nothing,
-- picking up the receiver is what a character remembers.
--
-- The record is keyed on the square and not on anything written into the
-- phone. The phone tiles are movable, and PhunInteriors' API table is clear
-- that a plain object's modData does not survive a pickup. So a phone
-- somebody carried off is noticed the next time its square loads without it,
-- and a phone of ours standing where nothing is recorded gets a record there
-- and then: an admin put it down from the item, or a wipe of global ModData
-- took its record and left its chunk. It is a spawn point like a built one,
-- not kept and not spaced. That is noticed when its square loads and when
-- somebody uses it, since one an admin just put down is on a square that has
-- already loaded.
--
-- A KEPT phone is the exception. An admin kept it, so it is in the store file
-- as well as here (store.lua), and it is never forgotten: a square that loads
-- without it gets one of ours put back, replacing a vanilla phone if one is
-- standing there. That is what brings it back in a new world after a wipe,
-- where the ModData record is gone and the file is not. It does not roll, and
-- it counts for PhoneDistance like any other, so the random swap spaces
-- itself around what an admin placed.
--
-- A phone a POINT asks for is the other exception. A point registered with
-- `phone` (a facing) wants one of ours standing behind it, so a character
-- who arrives there can call a taxi. It gets a record like any other phone,
-- marked with the point's id in `point`, and that record is treated as kept:
-- never forgotten, and put back when its square loads without it. It has no
-- point of its own, because the point that asked for it is its point: using
-- it grants that id, a ride to it goes there, and a ride from it starts
-- there. The records follow the registry (syncDeclared): a point that goes,
-- or is deleted, leaves its phone standing as an ordinary swapped phone, and
-- one that comes back takes it over again.
--
-- The POOL, in order. Each square in it (a CANDIDATE, Core.phones.candidates)
-- is given a random rank the first time this world sees it, kept in
-- Core.data.phoneRanks, and resolve walks them in rank order, taking each
-- that is far enough from every phone standing and every one taken so far.
-- Ranks, and not an order rolled as squares load, so which of a close group
-- wins is chance and not whichever side the first player came in from. A
-- taken square is recorded at once, `candidate` and `pending`, so it counts
-- for PhoneDistance from then on, and its phone goes up the first time its
-- square loads. From then on it is an ordinary swapped phone.
--
-- Only a pending phone is ever moved. Nobody has seen one, so resolve is run
-- again whenever the pool or the phones standing change, and it may take a
-- different square each time. Two things retire a square for the world
-- (Core.data.phoneDropped): a map phone whose square loads with no vanilla
-- phone on it (a map update moved it, or another map hides the cell), and a
-- phone of ours carried off. Either way the next in rank near it takes its
-- place. A wipe of global ModData takes the ranks, so a new world draws anew.
-- ---------------------------------------------------------------------------

-- How close a player must stand to use a phone, in squares either way. The
-- phone is used from the square in front, so two leaves room for a diagonal.
local REACH = 2

-- x -> y -> true for every recorded phone and every square in the pool, so
-- LoadGridsquare, which fires for every square that loads, can rule a square
-- out without building a key. Across levels: a square it names on another
-- level is ruled out by its key.
local index = {}

-- The pool's version resolve last ran for, and whether something it reads
-- has changed since: a phone standing or gone, a square dropped, a zone.
local resolvedVersion = nil
local dirty = true

-- Ranks are drawn from 0 to RANKS - 1. The last two digits are the square's
-- chance roll, so one number per square decides both.
local RANKS = 1000000

-- Squares per side of a bucket in resolve's spacing grid.
local BUCKET = 64

-- key -> {chance, spacing} for pool squares, so resolve asks PhunZones about
-- a square once per boot, not once per resolve. Cleared when the zones are.
local zoneCache = {}

PhoneSwap.ready = false

local keyOf = Core.phoneKey

-- The same id Core.phonePointId builds from a square, from the square key
-- the records are stored under: the id a phone with no point of its own
-- registers under.
function PhoneSwap.pointId(key)
    return "phun.spawn.phone." .. key
end

function PhoneSwap.store()
    Core.data.phones = Core.data.phones or {}
    return Core.data.phones
end

--- The id of the point a recorded phone grants: the point that asked for it,
--- or its own.
function PhoneSwap.idOf(key)
    local record = PhoneSwap.store()[key]
    return record and record.point or PhoneSwap.pointId(key)
end

local function indexSquare(x, y)
    index[x] = index[x] or {}
    index[x][y] = true
end

local function rebuildIndex()
    index = {}
    for _, record in pairs(PhoneSwap.store()) do
        indexSquare(record.x, record.y)
    end
    for _, c in pairs(Core.phones.candidates) do
        indexSquare(c.x, c.y)
    end
end

--- Is PhunZones installed and not yet set up? Its getLocation sets it up on
--- first call, and ours can come first: at our boot, and on squares that
--- load before its own first tick.
--
-- Never forced. Setting it up early runs its OnDataBuilt listeners before
-- there is a player, and in single player one of them indexed a nil player
-- and threw: after `inied` was set and before OnPhunZoneReady fired, so
-- PhunZones stayed half set up for the session.
local function zonesPending()
    local pz = PhunZones
    return pz ~= nil and pz.getLocation ~= nil and not pz.inied
end

--- PhunZones' resolved zone for a square, or nil without it, or before it
--- is set up (see zonesPending).
--
-- Soft and pcalled, the way PhunMart names a machine's region: PhunZones is
-- not a dependency, and its internals are not ours to depend on.
local function zoneAt(x, y)
    local pz = PhunZones
    if not (pz and pz.getLocation) or not pz.inied then
        return nil
    end
    local ok, loc = pcall(pz.getLocation, x, y)
    if not ok or type(loc) ~= "table" then
        return nil
    end
    return loc
end

--- A number a zone sets for a square, clamped, or `fallback` when no zone
--- sets it. tonumber, so a value left as text in an older zone config, or an
--- empty one, is unset rather than an error.
local function zoneNumber(x, y, field, fallback, least, most)
    local loc = zoneAt(x, y)
    local value = loc and tonumber(loc[field])
    if value == nil then
        return fallback
    end
    if value < least then
        return least
    end
    if most and value > most then
        return most
    end
    return value
end

--- PhoneChance where x, y is: the zone's `phoneChance` when PhunZones has
--- one set there, which is how an admin makes pay phones likelier in a town
--- than in the woods.
function PhoneSwap.chanceAt(x, y)
    return zoneNumber(x, y, Core.consts.zoneChanceField, Core.settings.PhoneChance or 0, 0, 100)
end

--- PhoneDistance where x, y is, the same way: the zone's `phoneDistance`.
--- It is the spacing of the phone being placed, not of the ones already
--- standing, so a dense zone can put a phone close to one just outside it.
function PhoneSwap.spacingAt(x, y)
    return zoneNumber(x, y, Core.consts.zoneDistanceField, Core.settings.PhoneDistance or 0, 0)
end

--- Where a square is, in words, from PhunZones when it is installed.
--- Returns (title, subtitle), either of which may be nil.
function PhoneSwap.locate(x, y)
    local loc = zoneAt(x, y)
    if not loc then
        return nil, nil
    end
    local title = loc.title ~= "" and loc.title or nil
    local subtitle = loc.subtitle ~= "" and loc.subtitle or nil
    return title, subtitle
end

--- What the picker shows, when the phone has no shipped or admin name: the
--- building a map puts it in (Core.phones.roomWords), with the zone's
--- subtitle before it when there is one. The room is read from the pool, not
--- kept on the record, so a regenerated map_phones.lua renames every phone
--- that has no name of its own at the next boot.
function PhoneSwap.labelFor(record, key)
    local candidate = key and Core.phones.candidates[key]
    local word = candidate and candidate.room and Core.phones.roomWords[candidate.room]
    if word then
        return record.subtitle and (record.subtitle .. " " .. word) or word
    end
    return record.subtitle and (record.subtitle .. " pay phone") or "Pay phone"
end

--- Register one record as a point. The region comes from PhunZones and is
--- nil without it, which the picker files under "Kentucky" (IGUI_PhunTaxi_Elsewhere).
---
--- A phone a point asked for registers nothing: that point is its point, and
--- is returned instead.
function PhoneSwap.registerRecord(key, record)
    if record.point then
        return Core.points[record.point]
    end
    local fx, fy = Core.phoneFront(record.x, record.y, record.facing)
    local id = PhoneSwap.pointId(key)
    return Core.registerPoint(id, {
        -- A shipped name is what the phone is registered as, so Reset name
        -- goes back to it rather than to "Pay phone".
        label = Store.shippedLabel(id) or PhoneSwap.labelFor(record, key),
        region = record.region,
        x = fx,
        y = fy,
        z = record.z or 0,
        -- Only a facing the table knows: registerPoint refuses any other,
        -- and an old record should still come up as a point.
        phone = Core.phones.front[record.facing] and record.facing or nil,
        discovery = Core.discovery.used,
        -- After the named places in the same town.
        priority = 10,
        saved = record.kept == true
    })
end

--- Bring the records in line with the phones the store file keeps: a kept
--- phone with no record gets one (the world was wiped), and a record the file
--- no longer keeps goes back to being an ordinary swapped phone.
function PhoneSwap.adopt()
    local store = PhoneSwap.store()
    for key, record in pairs(store) do
        if record.kept and not Core.saved.phones[key] then
            record.kept = nil
        end
    end
    for key, phone in pairs(Core.saved.phones) do
        local record = store[key]
        if not record then
            local region, subtitle = PhoneSwap.locate(phone.x, phone.y)
            record = {
                x = phone.x,
                y = phone.y,
                z = phone.z or 0,
                facing = phone.facing,
                region = region,
                subtitle = subtitle,
                created = Core.now()
            }
            store[key] = record
        end
        record.kept = true
    end
    rebuildIndex()
end

-- Whether the records have been located since boot. False until PhunZones is
-- ready, which is after our boot (see zonesPending), so a phone adopted at
-- boot starts with no region and gets one here.
PhoneSwap.located = false

--- Locate every record again, once per boot, on the first square load after
--- PhunZones is ready, and register any that changed. Without PhunZones it
--- runs on the first load and clears any region a record kept from a boot
--- that had it.
function PhoneSwap.relocate()
    PhoneSwap.located = true
    -- A zone may set its own chance and spacing, so the pool is taken again
    -- now that they can be read.
    zoneCache = {}
    dirty = true
    for key, record in pairs(PhoneSwap.store()) do
        local region, subtitle = PhoneSwap.locate(record.x, record.y)
        if region ~= record.region or subtitle ~= record.subtitle then
            record.region, record.subtitle = region, subtitle
            PhoneSwap.registerRecord(key, record)
        end
    end
end

--- Load the records and register them. Called from server_events' start,
--- once Core.data is the real ModData table and the store file has been
--- read: before that any record written would go into a table the load then
--- replaces, and no kept phone would be known.
function PhoneSwap.start()
    -- The one draw per world this replaced kept its results here.
    Core.data.candidates = nil
    PhoneSwap.adopt()
    for key, record in pairs(PhoneSwap.store()) do
        PhoneSwap.registerRecord(key, record)
    end
    -- After the records, so a phone whose point has gone since the last boot
    -- is registered once, by the sync, as an ordinary phone.
    PhoneSwap.syncDeclared()
    -- Not resolved here: a third party adding to the pool from
    -- OnInitGlobalModData may not have yet. The first square to load asks.
    resolvedVersion = nil
    dirty = true
    zoneCache = {}
    PhoneSwap.ready = true
end

-- The registry version the phone records last matched. See syncDeclared.
local syncedVersion = nil

--- Bring the records in line with the points that ask for a phone.
---
--- A point registered with `phone` gets a record at the square behind it,
--- owned by its id: made if there was none, taken over if a swapped or kept
--- phone already stood there (its own point goes). A record whose point no
--- longer asks for it, because the point went, was deleted or moved, goes
--- back to being an ordinary phone with a point of its own.
---
--- Asked before anything reads a record, and cheap when nothing changed:
--- points can register at any time, so this follows Core.registryVersion
--- rather than running once at boot.
function PhoneSwap.syncDeclared()
    if syncedVersion == Core.registryVersion then
        return
    end
    local store = PhoneSwap.store()

    -- phone key -> the point asking for it. Two asking for one square is a
    -- mistake, answered the same way every boot: the lower id wins.
    local owners = {}
    for id, point in pairs(Core.points) do
        local key = point.phoneKey
        if key and id ~= PhoneSwap.pointId(key) and (not owners[key] or id < owners[key].id) then
            owners[key] = point
        end
    end

    for key, record in pairs(store) do
        local owner = owners[key]
        if record.point and not (owner and owner.id == record.point) then
            record.point = nil
            PhoneSwap.registerRecord(key, record)
        end
    end

    for key, point in pairs(owners) do
        local record = store[key]
        if not record then
            local px, py = Core.phoneBehind(point.x, point.y, point.phone)
            record = {
                x = px,
                y = py,
                z = point.z or 0,
                created = Core.now()
            }
            store[key] = record
        end
        -- The point says which way its phone faces, and so which sprite goes
        -- back up.
        record.facing = point.phone
        if record.point ~= point.id then
            record.point = point.id
            Core.removePoint(PhoneSwap.pointId(key))
        end
    end

    rebuildIndex()
    syncedVersion = Core.registryVersion
end

--- Spacing grid for resolve: the points placed so far, bucketed, and flat.
local function newGrid()
    return {
        cells = {},
        all = {}
    }
end

local function gridAdd(grid, x, y)
    local bx, by = math.floor(x / BUCKET), math.floor(y / BUCKET)
    local column = grid.cells[bx]
    if not column then
        column = {}
        grid.cells[bx] = column
    end
    local cell = column[by]
    if not cell then
        cell = {}
        column[by] = cell
    end
    local p = {x, y}
    table.insert(cell, p)
    table.insert(grid.all, p)
end

local function nearAny(list, x, y, limit)
    for _, p in ipairs(list) do
        local dx, dy = p[1] - x, p[2] - y
        if (dx * dx) + (dy * dy) < limit then
            return true
        end
    end
    return false
end

--- Is x, y at least `distance` from everything in the grid? By bucket when
--- the distance is small, and down the flat list when it is so large that
--- the buckets to look in outnumber the points.
local function gridClear(grid, x, y, distance)
    if distance <= 0 then
        return true
    end
    local limit = distance * distance
    local span = math.ceil(distance / BUCKET)
    if (span * 2 + 1) * (span * 2 + 1) > #grid.all then
        return not nearAny(grid.all, x, y, limit)
    end
    local bx, by = math.floor(x / BUCKET), math.floor(y / BUCKET)
    for i = bx - span, bx + span do
        local column = grid.cells[i]
        if column then
            for j = by - span, by + span do
                local cell = column[j]
                if cell and nearAny(cell, x, y, limit) then
                    return false
                end
            end
        end
    end
    return true
end

--- A pool square's chance and spacing, from its zone, once per boot.
local function zoneOf(key, c)
    local z = zoneCache[key]
    if not z then
        z = {
            chance = c.chance or PhoneSwap.chanceAt(c.x, c.y),
            spacing = PhoneSwap.spacingAt(c.x, c.y)
        }
        zoneCache[key] = z
    end
    return z
end

--- Something resolve reads has changed, so the next square to load runs it.
function PhoneSwap.touch()
    dirty = true
end

--- Decide which squares in the pool get a phone. See the header.
---
--- Asked before a square is looked at, and cheap unless something changed:
--- the pool (Core.phones.candidatesVersion), a phone standing or gone, a
--- square dropped, or the zones. Never at boot, because a third party may
--- still be adding to the pool. A pending phone whose square is no longer in
--- the pool, moved in code because it was a wall, is dropped here.
---
--- `roll` is ZombRand in game, a parameter so the spec can rank without it.
--- Returns true if it ran.
function PhoneSwap.resolve(roll)
    if not dirty and resolvedVersion == Core.phones.candidatesVersion then
        return false
    end
    roll = roll or ZombRand
    -- A point's phone counts for the spacing, so it has to be recorded first.
    PhoneSwap.syncDeclared()
    local store = PhoneSwap.store()
    local candidates = Core.phones.candidates
    Core.data.phoneRanks = Core.data.phoneRanks or {}
    Core.data.phoneDropped = Core.data.phoneDropped or {}
    local ranks, dropped = Core.data.phoneRanks, Core.data.phoneDropped

    -- Every phone that is not pending stays where it is, and spaces the rest.
    local grid = newGrid()
    for _, record in pairs(store) do
        if not record.pending then
            gridAdd(grid, record.x, record.y)
        end
    end

    -- The squares still in play: offered, not retired, and not already a
    -- phone of ours (kept, a point's, built, or one that went up).
    local keys, unranked = {}, {}
    for key in pairs(candidates) do
        local record = store[key]
        if not dropped[key] and not (record and not record.pending) then
            table.insert(keys, key)
            if ranks[key] == nil then
                table.insert(unranked, key)
            end
        end
    end
    -- New squares ranked in key order, so the same rolls rank them the same.
    Core.tools.sort(unranked)
    for _, key in ipairs(unranked) do
        ranks[key] = roll(RANKS)
    end
    Core.tools.sort(keys, function(a, b)
        if ranks[a] ~= ranks[b] then
            return ranks[a] < ranks[b]
        end
        return a < b
    end)

    local taken = {}
    for _, key in ipairs(keys) do
        local c = candidates[key]
        local zone = zoneOf(key, c)
        if ranks[key] % 100 < zone.chance and gridClear(grid, c.x, c.y, zone.spacing) then
            taken[key] = true
            gridAdd(grid, c.x, c.y)
        end
    end

    local moved = 0
    for key, record in pairs(store) do
        if record.pending and not taken[key] then
            store[key] = nil
            Core.removePoint(PhoneSwap.pointId(key))
            moved = moved + 1
        end
    end
    local fresh = {}
    for key in pairs(taken) do
        if not store[key] then
            local c = candidates[key]
            -- Located now, not left for settle: relocate has already run
            -- this boot, so a phone taken after it would otherwise sit in no
            -- region (the editor's "Kentucky" fallback) until its square loads.
            -- Resolve runs only once PhunZones can answer.
            local region, subtitle = PhoneSwap.locate(c.x, c.y)
            local record = {
                x = c.x,
                y = c.y,
                z = c.z,
                facing = c.facing,
                region = region,
                subtitle = subtitle,
                candidate = true,
                pending = true,
                created = Core.now()
            }
            store[key] = record
            PhoneSwap.registerRecord(key, record)
            table.insert(fresh, record)
        end
    end

    dirty = false
    resolvedVersion = Core.phones.candidatesVersion
    rebuildIndex()
    if moved > 0 or #fresh > 0 then
        Core.logLn("pay phone pool: " .. #keys .. " squares in play, " .. #fresh .. " taken, " .. moved ..
                       " let go")
    end

    -- One taken on a square that has already loaded would otherwise wait for
    -- it to load again.
    local cell = getCell()
    for _, record in ipairs(fresh) do
        local square = cell and cell:getGridSquare(record.x, record.y, record.z)
        if square then
            PhoneSwap.visit(square)
        end
    end
    return true
end

--- Retire a pool square for this world, and let the next in rank near it
--- have its place.
function PhoneSwap.drop(key, why)
    local store = PhoneSwap.store()
    if store[key] and store[key].pending then
        store[key] = nil
        Core.removePoint(PhoneSwap.pointId(key))
    end
    Core.data.phoneDropped = Core.data.phoneDropped or {}
    Core.data.phoneDropped[key] = true
    dirty = true
    Core.logLn("pay phone at " .. key .. " " .. why .. ", so another nearby may take its place")
end

--- Is x, y at least PhoneDistance (or its zone's, see spacingAt) from every
--- recorded phone? Squared distance, on every level, so a phone upstairs
--- still spaces one below.
---
--- `distance` overrides PhoneDistance, for a phone a player builds, which
--- has its own spacing and no zone override.
function PhoneSwap.farEnough(x, y, distance)
    distance = distance or PhoneSwap.spacingAt(x, y)
    if distance <= 0 then
        return true
    end
    local limit = distance * distance
    for _, record in pairs(PhoneSwap.store()) do
        local dx, dy = record.x - x, record.y - y
        if (dx * dx) + (dy * dy) < limit then
            return false
        end
    end
    return true
end

--- Record a swapped phone and register it. Returns the point.
function PhoneSwap.add(x, y, z, facing)
    local key = keyOf(x, y, z)
    local region, subtitle = PhoneSwap.locate(x, y)
    local record = {
        x = x,
        y = y,
        z = z or 0,
        facing = facing,
        region = region,
        subtitle = subtitle,
        created = Core.now()
    }
    PhoneSwap.store()[key] = record
    indexSquare(x, y)
    -- A pending phone too near this one has to give way.
    dirty = true
    Core.debugLn("pay phone at " .. key .. " (" .. tostring(region) .. ")")
    return PhoneSwap.registerRecord(key, record)
end

--- Forget the phone recorded at a square. Its point goes with it, and a
--- character who had used it keeps the id in their list, filtered on read,
--- like any other removed point.
---
--- Never a kept phone: that is put back instead, and has to be released
--- first to be forgotten. Nor one a point asked for, which is put back too,
--- nor a pending one whose phone has not gone up yet.
---
--- A square in the pool is retired for the world as it goes, so the phone is
--- not put straight back: somebody took it, and the next in rank nearby
--- takes its place instead.
function PhoneSwap.forget(x, y, z)
    local key = keyOf(x, y, z)
    local store = PhoneSwap.store()
    if not store[key] or store[key].kept or store[key].point or store[key].pending then
        return false
    end
    store[key] = nil
    Core.removePoint(PhoneSwap.pointId(key))
    dirty = true
    if Core.phones.candidates[key] then
        Core.data.phoneDropped = Core.data.phoneDropped or {}
        Core.data.phoneDropped[key] = true
    end
    rebuildIndex()
    Core.logLn("pay phone at " .. key .. " is gone, so it is no longer a spawn point")
    return true
end

--- Record a phone of ours found standing on a square with no record, and
--- register it. Returns the point.
---
--- Not spaced against other phones: somebody put this one here on purpose,
--- which is the decision PhoneDistance only stands in for. Not kept either,
--- so like a built phone it goes with a wipe unless an admin keeps it.
function PhoneSwap.recordStanding(square, spriteName)
    local x, y, z = square:getX(), square:getY(), square:getZ()
    Core.logLn("pay phone at " .. keyOf(x, y, z) .. " had no record, so it is a spawn point now")
    return PhoneSwap.add(x, y, z, Core.phoneFacing(spriteName))
end

--- Put our phone where `old` stands, or on the square when `old` is nil.
--- Returns true if it did.
--
-- The placement is PhunMart's, call for call, and for PhunMart's reasons: the
-- complete item packet does not reliably carry a modded sprite, so the sprite
-- is sent again by name, and the square only blocks movement once it has
-- folded the new sprite's solid flag into its own properties.
--
-- The sprite is checked BEFORE the old phone comes off. Demolishing first and
-- finding nothing to put back leaves a hole where a phone was.
---
--- `stamp`, when given, is written into the new phone's modData before it
--- is sent to clients, so it arrives with the object: the builder's key, for
--- a phone a player built.
function PhoneSwap.replace(square, old, spriteName, stamp)
    if not getSprite(spriteName) then
        Core.logLn("no sprite '" .. tostring(spriteName) .. "', so the phone at " .. square:getX() .. "," ..
                       square:getY() .. " stays vanilla")
        return false
    end
    if old then
        square:transmitRemoveItemFromSquare(old)
    end
    local phone = IsoObject.new(square:getCell(), square, spriteName)
    local md = phone:getModData()
    for k, v in pairs(stamp or {}) do
        md[k] = v
    end
    square:AddSpecialObject(phone, -1)
    phone:transmitCompleteItemToClients()
    phone:transmitUpdatedSpriteToClients()
    square:RecalcProperties()
    square:RecalcAllWithNeighbours(true)
    -- Clients note phones for the ring on LoadGridsquare, which has already
    -- run for this square: in single player the client's listener is added
    -- first, and in MP the new object reaches the client after its load.
    Core.broadcast(Core.commands.phoneUp, {
        x = square:getX(),
        y = square:getY(),
        z = square:getZ()
    })
    return true
end

--- LoadGridsquare. Fires for every square that loads, so the common case, a
--- square neither the pool nor a record names, is two table lookups and out.
function PhoneSwap.loadGridsquare(square)
    if not PhoneSwap.ready or not square then
        return
    end
    if not PhoneSwap.located and not zonesPending() then
        PhoneSwap.relocate()
    end
    PhoneSwap.syncDeclared()
    -- Not while PhunZones cannot yet say what a zone's chance and spacing
    -- are. A pending phone from an earlier boot still goes up meanwhile.
    if not zonesPending() then
        PhoneSwap.resolve()
    end
    local column = index[square:getX()]
    if column == nil or column[square:getY()] == nil then
        return
    end
    PhoneSwap.visit(square)
end

--- Put a kept phone, or a point's, back on its square, replacing `old` when
--- that is a vanilla phone standing there. The sprite is the facing's, never
--- a stored one: a record carrying its own could disagree with its facing,
--- or name a sprite since dropped from the table, which would be put back as
--- a phone nothing recognises.
function PhoneSwap.restore(square, record, old)
    local spriteName = Core.phoneSpriteFor(record.facing, ZombRand)
    if not (spriteName and PhoneSwap.replace(square, old, spriteName)) then
        return false
    end
    local key = keyOf(record.x, record.y, record.z)
    if record.pending then
        PhoneSwap.settle(key, record)
        Core.logLn("pay phone candidate at " .. key .. " put up")
        return true
    end
    Core.logLn((record.point and ("pay phone for " .. record.point) or "kept pay phone") .. " at " .. key ..
                   " put back")
    return true
end

--- A drawn candidate's phone is standing: from now on it is an ordinary
--- swapped phone. Its place is looked up now, since it was drawn before its
--- square was anywhere near a player and PhunZones may not have been ready.
function PhoneSwap.settle(key, record)
    record.pending = nil
    record.region, record.subtitle = PhoneSwap.locate(record.x, record.y)
    PhoneSwap.registerRecord(key, record)
end

--- What stands on a square: our phone and its sprite name, and the first
--- vanilla phone that could be swapped and its facing.
local function phonesOn(square)
    local ours, oursName, vanilla, vanillaFacing
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        local sprite = obj:getSprite()
        local name = sprite and sprite:getName()
        if name and not ours and Core.phoneFacing(name) then
            ours, oursName = obj, name
        elseif name and not vanilla and Core.phoneTargetFacing(name) then
            vanilla, vanillaFacing = obj, Core.phoneTargetFacing(name)
        end
    end
    return ours, oursName, vanilla, vanillaFacing
end
PhoneSwap.phonesOn = phonesOn
PhoneSwap.keyOf = keyOf

--- A loaded square the pool or a record names: bring what stands on it in
--- line with what is recorded.
function PhoneSwap.visit(square)
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local key = keyOf(x, y, z)
    local record = PhoneSwap.store()[key]
    local offered = Core.phones.candidates[key]
    if not record and not offered then
        -- The index is by column, so this is another level of a square it
        -- names.
        return
    end
    local ours, oursName, vanilla, vanillaFacing = phonesOn(square)

    if not record then
        -- In the pool and not taken, or retired: only one of ours standing
        -- here is news, which is how the phones come back after a wipe of
        -- global ModData.
        if ours then
            PhoneSwap.recordStanding(square, oursName)
        end
        return
    end
    if ours then
        if record.pending then
            -- One of ours was already here, so there is nothing to put up.
            PhoneSwap.settle(key, record)
        end
        return
    end
    if record.pending and offered and offered.replace then
        if not vanilla then
            PhoneSwap.drop(key, "has no vanilla phone to replace")
            return
        end
        -- What stands here decides which way ours faces.
        record.facing = vanillaFacing
    end
    -- Kept, a point's, or taken from the pool, so put up, over the vanilla
    -- phone a new world has here.
    if record.kept or record.point or record.pending then
        PhoneSwap.restore(square, record, vanilla)
        return
    end
    -- Recorded here and not standing here: somebody carried it off.
    PhoneSwap.forget(x, y, z)
end

--- The squares of phones standing that the pool does not name (kept, built,
--- a point's, one put down from an item), for the client, whose ring looks
--- only at squares it has been told of. The pool is shared code, so the
--- client knows those already.
function PhoneSwap.standingKeys()
    local out = {}
    for key, record in pairs(PhoneSwap.store()) do
        if not record.pending and not Core.phones.candidates[key] then
            table.insert(out, key)
        end
    end
    Core.tools.sort(out)
    return out
end

--- Keep the phone on a square across wipes. An admin action.
---
--- One of ours is recorded if it was not (one placed from an item, say). A
--- vanilla phone is swapped for ours first, whatever its roll said and
--- however near another phone is: an admin putting one here is the decision
--- the roll and the spacing only stand in for.
---
--- With `facing` (E, S, W or N), a square with no phone on it at all gets a
--- new one of ours facing that way. Without it, such a square is refused. A
--- phone already there is kept as it faces, whatever `facing` says.
---
--- Returns the point, or nil and a translation key.
function PhoneSwap.keep(x, y, z, facing)
    if facing ~= nil and not Core.phones.front[facing] then
        return nil, "IGUI_PhunTaxi_CannotPlacePhone"
    end
    local square = getCell():getGridSquare(x, y, z or 0)
    if not square then
        return nil, "IGUI_PhunTaxi_NoPhoneHere"
    end
    local key = keyOf(x, y, z)
    local ours, oursName, vanilla, vanillaFacing = phonesOn(square)
    if ours then
        local existing = PhoneSwap.store()[key]
        if not existing then
            PhoneSwap.add(x, y, z, Core.phoneFacing(oursName))
        elseif existing.pending then
            PhoneSwap.settle(key, existing)
        end
    elseif vanilla then
        local spriteName = Core.phoneSpriteFor(vanillaFacing, ZombRand)
        if not (spriteName and PhoneSwap.replace(square, vanilla, spriteName)) then
            return nil, "IGUI_PhunTaxi_NoPhoneHere"
        end
        PhoneSwap.add(x, y, z, vanillaFacing)
    elseif facing then
        -- No phone here at all, and the admin asked for one facing this way.
        local spriteName = Core.phoneSpriteFor(facing, ZombRand)
        if not (spriteName and PhoneSwap.replace(square, nil, spriteName)) then
            return nil, "IGUI_PhunTaxi_CannotPlacePhone"
        end
        PhoneSwap.add(x, y, z, facing)
    else
        return nil, "IGUI_PhunTaxi_NoPhoneHere"
    end

    local record = PhoneSwap.store()[key]
    if not Store.keepPhone(key, record) then
        return nil, "IGUI_PhunTaxi_NotSaved"
    end
    record.kept = true
    return PhoneSwap.registerRecord(key, record)
end

--- Stop keeping a phone. It stays where it is, as an ordinary swapped phone,
--- and is not in the next world. Takes the key the point id is built from.
function PhoneSwap.release(key)
    local record = PhoneSwap.store()[key]
    if not record or not record.kept then
        return nil, "IGUI_PhunTaxi_NotKept"
    end
    if not Store.releasePhone(key) then
        return nil, "IGUI_PhunTaxi_NotSaved"
    end
    record.kept = nil
    return PhoneSwap.registerRecord(key, record)
end

--- What to tell a client that just found `point`. A phone found by walking
--- near it carries its own square, so the client can ring it once there:
--- the cue that it counted, since nothing was picked up.
function PhoneSwap.announcement(point)
    local key = PhoneSwap.keyOfPoint(point.id)
    local record = key and PhoneSwap.store()[key]
    if not record then
        return {
            id = point.id,
            label = point.label,
            point = Unlocks.entryFor(point, true)
        }
    end
    return {
        id = point.id,
        label = point.label,
        point = Unlocks.entryFor(point, true),
        text = "IGUI_PhunTaxi_PhoneFound",
        phone = {
            x = record.x,
            y = record.y,
            z = record.z or 0
        }
    }
end

--- The record key out of a phone's point id, or nil when it is not one. A
--- point that asked for a phone answers with its phone's key.
function PhoneSwap.keyOfPoint(id)
    if type(id) ~= "string" then
        return nil
    end
    local prefix = PhoneSwap.pointId("")
    if id:sub(1, #prefix) == prefix then
        return id:sub(#prefix + 1)
    end
    PhoneSwap.syncDeclared()
    local point = Core.points[id]
    local record = point and point.phoneKey and PhoneSwap.store()[point.phoneKey]
    return record and record.point == id and point.phoneKey or nil
end

--- A player picked up the receiver. Returns (point, granted), or (nil, why)
--- with `why` a translation key for the player.
--
-- Checked here and not trusted from the client: the player has to be standing
-- at the phone, the square has to hold one of ours, and it has to be one the
-- swap recorded. Each use refreshes where the phone is, since PhunZones may
-- not have been ready when the square first loaded, and logs the phone's
-- position and location to the console.
function PhoneSwap.use(player, args)
    local key, record = PhoneSwap.phoneAt(player, args)
    if not key then
        -- `record` is the reason here, a translation key.
        return nil, record
    end
    local x, y = record.x, record.y

    local region, subtitle = PhoneSwap.locate(x, y)
    if region ~= record.region or subtitle ~= record.subtitle then
        record.region, record.subtitle = region, subtitle
        PhoneSwap.registerRecord(key, record)
    end

    local id = PhoneSwap.idOf(key)
    local point = Core.points[id] or PhoneSwap.registerRecord(key, record)
    local granted = Unlocks.grant(player, id)
    Core.logLn(tostring(Core.playerKey(player)) .. " used the pay phone at " .. key .. ", location " ..
                   tostring(region or "unzoned") .. (subtitle and (" / " .. subtitle) or "") .. ", point " .. id)
    return point, granted
end

--- Is this player standing at a recorded phone of ours on the square in
--- `args` ({x, y, z})? Returns (key, record), or (nil, why) with `why` a
--- translation key. The check every phone command starts with: the use, and
--- a taxi called from it.
function PhoneSwap.phoneAt(player, args)
    local x, y, z = tonumber(args and args.x), tonumber(args and args.y), tonumber(args and args.z) or 0
    if not x or not y then
        return nil, "IGUI_PhunTaxi_PhoneDead"
    end
    if math.abs(math.floor(player:getX()) - x) > REACH or math.abs(math.floor(player:getY()) - y) > REACH or
        math.floor(player:getZ()) ~= z then
        return nil, "IGUI_PhunTaxi_PhoneTooFar"
    end

    PhoneSwap.syncDeclared()
    local key = keyOf(x, y, z)
    local record = PhoneSwap.store()[key]
    local square = getCell():getGridSquare(x, y, z)
    if square then
        local ours, oursName = phonesOn(square)
        if record and not ours then
            PhoneSwap.forget(x, y, z)
            record = nil
        elseif ours and not record then
            -- Put down on a square that had already loaded, so LoadGridsquare
            -- never saw it.
            PhoneSwap.recordStanding(square, oursName)
            record = PhoneSwap.store()[key]
        end
    end
    if not record then
        return nil, "IGUI_PhunTaxi_PhoneDead"
    end
    return key, record
end

Core.modules.phoneSwap = PhoneSwap
return PhoneSwap
