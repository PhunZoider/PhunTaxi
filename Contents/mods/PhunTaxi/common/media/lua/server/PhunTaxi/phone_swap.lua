if isClient() then
    return
end
require "PhunSpawn/points"
require "PhunSpawn/phones"
local Core = PhunSpawn
local Unlocks = require "PhunSpawn/unlocks"
local Store = require "PhunSpawn/store"
local PhoneSwap = {}

-- ---------------------------------------------------------------------------
-- Swapping vanilla pay phones for ours, and making each one a spawn point.
--
-- PhunMart's vending machine swap, applied to phones. On LoadGridsquare a
-- vanilla phone listed in Core.phones.targets gets ONE roll: it is stamped
-- win or lose, so a chunk loading again does not roll it again. A win at
-- PhoneChance percent swaps it for ours, unless a swapped phone already
-- stands within PhoneDistance, which is what stops one street having three.
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
-- and a phone somebody put down elsewhere is simply a phone: it is not a
-- spawn point, and using it says the line is dead.
--
-- A KEPT phone is the exception. An admin kept it, so it is in the store file
-- as well as here (store.lua), and it is never forgotten: a square that loads
-- without it gets one of ours put back, replacing a vanilla phone if one is
-- standing there. That is what brings it back in a new world after a wipe,
-- where the ModData record is gone and the file is not. It does not roll, and
-- it counts for PhoneDistance like any other, so the random swap spaces
-- itself around what an admin placed.
-- ---------------------------------------------------------------------------

-- How close a player must stand to use a phone, in squares either way. The
-- phone is used from the square in front, so two leaves room for a diagonal.
local REACH = 2

-- x -> y -> true for every recorded phone, so LoadGridsquare, which fires for
-- every square that loads, can rule a square out without building a key.
local index = {}

PhoneSwap.ready = false

local function keyOf(x, y, z)
    return tostring(x) .. "_" .. tostring(y) .. "_" .. tostring(z or 0)
end

-- The same id Core.phonePointId builds from a square, from the square key
-- the records are stored under. The client relies on the two agreeing.
function PhoneSwap.pointId(key)
    return "phun.spawn.phone." .. key
end

function PhoneSwap.store()
    Core.data.phones = Core.data.phones or {}
    return Core.data.phones
end

local function rebuildIndex()
    index = {}
    for _, record in pairs(PhoneSwap.store()) do
        index[record.x] = index[record.x] or {}
        index[record.x][record.y] = true
    end
end

--- Where a square is, in words, from PhunZones when it is installed.
--
-- Soft and pcalled, the way PhunMart names a machine's region: PhunZones is
-- not a dependency, and its internals are not ours to depend on. Returns
-- (title, subtitle), either of which may be nil.
function PhoneSwap.locate(x, y)
    local pz = PhunZones
    if not (pz and pz.getLocation) then
        return nil, nil
    end
    local ok, loc = pcall(pz.getLocation, x, y)
    if not ok or type(loc) ~= "table" then
        return nil, nil
    end
    local title = loc.title ~= "" and loc.title or nil
    local subtitle = loc.subtitle ~= "" and loc.subtitle or nil
    return title, subtitle
end

--- What the picker shows. The coordinates are in it because a town can hold
--- several phones and "Pay phone" three times over is no choice at all.
function PhoneSwap.labelFor(record)
    local what = record.subtitle and (record.subtitle .. " pay phone") or "Pay phone"
    return what .. " (" .. tostring(record.x) .. ", " .. tostring(record.y) .. ")"
end

--- Register one record as a point. The region comes from PhunZones and is
--- nil without it, which the picker files under "Elsewhere".
function PhoneSwap.registerRecord(key, record)
    local fx, fy = Core.phoneFront(record.x, record.y, record.facing)
    return Core.registerPoint(PhoneSwap.pointId(key), {
        label = PhoneSwap.labelFor(record),
        region = record.region,
        x = fx,
        y = fy,
        z = record.z or 0,
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
                sprite = phone.sprite,
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

--- Load the records and register them. Called from server_events' start,
--- once Core.data is the real ModData table and the store file has been
--- read: before that any record written would go into a table the load then
--- replaces, and no kept phone would be known.
function PhoneSwap.start()
    PhoneSwap.adopt()
    for key, record in pairs(PhoneSwap.store()) do
        PhoneSwap.registerRecord(key, record)
    end
    PhoneSwap.ready = true
end

--- Is x, y at least PhoneDistance from every recorded phone? Squared
--- distance, on every level, so a phone upstairs still spaces one below.
---
--- `distance` overrides PhoneDistance, for a phone a player builds, which
--- has its own spacing.
function PhoneSwap.farEnough(x, y, distance)
    distance = distance or Core.settings.PhoneDistance or 0
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
function PhoneSwap.add(x, y, z, facing, spriteName)
    local key = keyOf(x, y, z)
    local region, subtitle = PhoneSwap.locate(x, y)
    local record = {
        x = x,
        y = y,
        z = z or 0,
        facing = facing,
        sprite = spriteName,
        region = region,
        subtitle = subtitle,
        created = Core.now()
    }
    PhoneSwap.store()[key] = record
    index[x] = index[x] or {}
    index[x][y] = true
    Core.debugLn("pay phone at " .. key .. " (" .. tostring(region) .. ")")
    return PhoneSwap.registerRecord(key, record)
end

--- Forget the phone recorded at a square. Its point goes with it, and a
--- character who had used it keeps the id in their list, filtered on read,
--- like any other removed point.
---
--- Never a kept phone: that is put back instead, and has to be released
--- first to be forgotten.
function PhoneSwap.forget(x, y, z)
    local key = keyOf(x, y, z)
    local store = PhoneSwap.store()
    if not store[key] or store[key].kept then
        return false
    end
    store[key] = nil
    Core.removePoint(PhoneSwap.pointId(key))
    rebuildIndex()
    Core.logLn("pay phone at " .. key .. " is gone, so it is no longer a spawn point")
    return true
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
    md[Core.consts.phoneRolledKey] = true
    for k, v in pairs(stamp or {}) do
        md[k] = v
    end
    square:AddSpecialObject(phone, -1)
    phone:transmitCompleteItemToClients()
    phone:transmitUpdatedSpriteToClients()
    square:RecalcProperties()
    square:RecalcAllWithNeighbours(true)
    return true
end

--- The one roll a vanilla phone gets.
function PhoneSwap.roll(square, obj, facing)
    local md = obj:getModData()
    if md[Core.consts.phoneRolledKey] then
        return
    end
    -- Stamped before the roll, so a loss is as final as a win.
    md[Core.consts.phoneRolledKey] = true

    if ZombRand(100) >= (Core.settings.PhoneChance or 0) then
        return
    end
    local x, y, z = square:getX(), square:getY(), square:getZ()
    if not PhoneSwap.farEnough(x, y) then
        return
    end
    local spriteName = Core.phoneSpriteFor(facing, ZombRand)
    if spriteName and PhoneSwap.replace(square, obj, spriteName) then
        PhoneSwap.add(x, y, z, facing, spriteName)
    end
end

--- LoadGridsquare. Fires for every square that loads, so the common case, a
--- square with no phone on it and none recorded, has to cost next to nothing.
function PhoneSwap.loadGridsquare(square)
    if not PhoneSwap.ready or not square then
        return
    end
    local x, y = square:getX(), square:getY()
    local column = index[x]
    local record = column ~= nil and column[y] == true and PhoneSwap.store()[keyOf(x, y, square:getZ())] or nil
    -- Zero turns the swap off and leaves phones unstamped, so turning it on
    -- later still gives every phone its roll.
    local swapping = (Core.settings.PhoneChance or 0) > 0

    local objects = square:getObjects()
    local found, candidate, candidateFacing = false, nil, nil
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        local sprite = obj:getSprite()
        local name = sprite and sprite:getName()
        if name then
            if record and Core.phoneFacing(name) then
                found = true
            elseif (swapping or record) and not candidate then
                local facing = Core.phoneTargetFacing(name)
                if facing then
                    candidate, candidateFacing = obj, facing
                end
            end
        end
    end

    if record and not found then
        -- Kept, so put back, over the vanilla phone a new world has here.
        if record.kept then
            PhoneSwap.restore(square, record, candidate)
            return
        end
        -- Recorded here and not standing here: somebody carried it off.
        PhoneSwap.forget(x, y, square:getZ())
    end
    if candidate and swapping then
        PhoneSwap.roll(square, candidate, candidateFacing)
    end
end

--- Put a kept phone back on its square, replacing `old` when that is a
--- vanilla phone standing there. Its own sprite when that is still one of
--- ours, since a sprite dropped from the table since would be put back as a
--- phone nothing recognises.
function PhoneSwap.restore(square, record, old)
    local spriteName = record.sprite
    if not (spriteName and Core.phoneFacing(spriteName)) then
        spriteName = Core.phoneSpriteFor(record.facing, ZombRand)
    end
    if not (spriteName and PhoneSwap.replace(square, old, spriteName)) then
        return false
    end
    record.sprite = spriteName
    Core.logLn("kept pay phone at " .. keyOf(record.x, record.y, record.z) .. " put back")
    return true
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
        return nil, "IGUI_PhunSpawn_CannotPlacePhone"
    end
    local square = getCell():getGridSquare(x, y, z or 0)
    if not square then
        return nil, "IGUI_PhunSpawn_NoPhoneHere"
    end
    local key = keyOf(x, y, z)
    local ours, oursName, vanilla, vanillaFacing = phonesOn(square)
    if ours then
        if not PhoneSwap.store()[key] then
            PhoneSwap.add(x, y, z, Core.phoneFacing(oursName), oursName)
        end
    elseif vanilla then
        local spriteName = Core.phoneSpriteFor(vanillaFacing, ZombRand)
        if not (spriteName and PhoneSwap.replace(square, vanilla, spriteName)) then
            return nil, "IGUI_PhunSpawn_NoPhoneHere"
        end
        PhoneSwap.add(x, y, z, vanillaFacing, spriteName)
    elseif facing then
        -- No phone here at all, and the admin asked for one facing this way.
        local spriteName = Core.phoneSpriteFor(facing, ZombRand)
        if not (spriteName and PhoneSwap.replace(square, nil, spriteName)) then
            return nil, "IGUI_PhunSpawn_CannotPlacePhone"
        end
        PhoneSwap.add(x, y, z, facing, spriteName)
    else
        return nil, "IGUI_PhunSpawn_NoPhoneHere"
    end

    local record = PhoneSwap.store()[key]
    if not Store.keepPhone(key, record) then
        return nil, "IGUI_PhunSpawn_NotSaved"
    end
    record.kept = true
    return PhoneSwap.registerRecord(key, record)
end

--- Stop keeping a phone. It stays where it is, as an ordinary swapped phone,
--- and is not in the next world. Takes the key the point id is built from.
function PhoneSwap.release(key)
    local record = PhoneSwap.store()[key]
    if not record or not record.kept then
        return nil, "IGUI_PhunSpawn_NotKept"
    end
    if not Store.releasePhone(key) then
        return nil, "IGUI_PhunSpawn_NotSaved"
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
            label = point.label
        }
    end
    return {
        id = point.id,
        label = point.label,
        text = "IGUI_PhunSpawn_PhoneFound",
        phone = {
            x = record.x,
            y = record.y,
            z = record.z or 0
        }
    }
end

--- The record key out of a phone's point id, or nil when it is not one.
function PhoneSwap.keyOfPoint(id)
    local prefix = PhoneSwap.pointId("")
    if type(id) ~= "string" or id:sub(1, #prefix) ~= prefix then
        return nil
    end
    return id:sub(#prefix + 1)
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

    local id = PhoneSwap.pointId(key)
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
        return nil, "IGUI_PhunSpawn_PhoneDead"
    end
    if math.abs(math.floor(player:getX()) - x) > REACH or math.abs(math.floor(player:getY()) - y) > REACH or
        math.floor(player:getZ()) ~= z then
        return nil, "IGUI_PhunSpawn_PhoneTooFar"
    end

    local key = keyOf(x, y, z)
    local record = PhoneSwap.store()[key]
    local square = getCell():getGridSquare(x, y, z)
    if record and square then
        local standing = false
        local objects = square:getObjects()
        for i = 0, objects:size() - 1 do
            local sprite = objects:get(i):getSprite()
            if sprite and Core.phoneFacing(sprite:getName()) then
                standing = true
                break
            end
        end
        if not standing then
            PhoneSwap.forget(x, y, z)
            record = nil
        end
    end
    if not record then
        return nil, "IGUI_PhunSpawn_PhoneDead"
    end
    return key, record
end

Core.modules.phoneSwap = PhoneSwap
return PhoneSwap
