require "PhunTaxi/core"
require "PhunTaxi/tools"
local Core = PhunTaxi

-- ---------------------------------------------------------------------------
-- Pay phones: which vanilla tiles get swapped, and for what.
--
-- The same idea as PhunMart's vending machines. A vanilla pay phone gets one
-- roll, the first time its square loads, at PhoneChance percent, and only if
-- no swapped phone already stands within PhoneDistance. A phone that wins is
-- replaced by one of ours, and ours is a spawn point: using it is how a
-- character comes to know it. The roll and the swap are server side, see
-- server/phone_swap.lua. This file is the shared half, because the client has
-- to recognise one of our phones to offer the context menu.
--
-- Keyed by FACING on both sides, so a target and a replacement are one line
-- each and neither has to know about the other:
--
--   targets  vanilla sprite -> "E" | "S" | "W" | "N"
--   sprites  facing -> our sprite, or a list of them to pick from at random
--
-- Adding a target is Core.addPhoneTarget(sprite, facing). Changing or adding
-- a replacement is Core.addPhoneSprite(facing, sprite). Both are safe from
-- any hook that runs before the first square loads.
-- ---------------------------------------------------------------------------

Core.phones = {
    targets = {
        ["street_decoration_01_38"] = "E",
        ["street_decoration_01_39"] = "S",
        ["street_decoration_01_46"] = "W",
        ["street_decoration_01_47"] = "N"
    },
    sprites = {
        E = "phuninteriors_01_16",
        S = "phuninteriors_01_17",
        W = "phuninteriors_01_18",
        N = "phuninteriors_01_19"
    },
    -- What an unused phone rings with, for PhoneRingSeconds. Ours, in
    -- scripts/PhunTaxi_Sounds.txt. It loops, so it is stopped when the time
    -- is up or the phone is answered, and each phone rings once a session.
    -- Real time rather than game time on purpose: ten game minutes
    -- is 25 seconds on a one hour day and ten minutes on a 24 hour one. Its
    -- distanceMax is 30, so PhoneRingRange (default 30) should stay at or
    -- under that: a ring further off is one nobody hears, and it still uses
    -- up that phone's ring for the session.
    ringSound = "PhunTaxi_PhoneRinging",
    -- Played on the rider once a taxi has put them down, the free ride out of
    -- the spawn room included: the cab pulling away from where they stand.
    driveOffSound = "PhunTaxi_DriveOff",
    -- Where the character stands to use a phone, and so where they wake up
    -- when they spawn at one. The phone's own square is solid.
    front = {
        E = {1, 0},
        S = {0, 1},
        W = {-1, 0},
        N = {0, -1}
    },
    -- Squares a phone MAY go on: phone key -> {x, y, z, facing, chance,
    -- replace, room}. The phones the maps put down (Core.addMapPhone, `replace`
    -- set) and squares with no phone at all (Core.addPhoneCandidate). The
    -- server ranks them once per world at random (PhoneSwap.resolve) and
    -- takes each in rank order that is PhoneDistance from every phone taken
    -- or standing. So a handful close together gives one phone, somewhere
    -- different each world.
    candidates = {},
    -- Counts every change to `candidates`, so the draw knows when a late one
    -- has turned up without walking the table on every square load.
    candidatesVersion = 0,
    -- What a map phone is called after the room it is in (addMapPhone's
    -- `room`, which scripts/phones.pl reads out of the lotheader: the phone's
    -- own room when it says something, or else the biggest telling room of
    -- its building). A room not here labels the phone by its zone alone, so
    -- a room that could be anything is left out rather than guessed at.
    roomWords = {
        armysurplus = "Army surplus",
        bakery = "Bakery",
        bakerykitchen = "Bakery",
        bank = "Bank",
        bar = "Bar",
        barstorage = "Bar",
        bookstore = "Bookstore",
        cafe = "Cafe",
        cafeteria = "Cafeteria",
        cafeteriakitchen = "Cafeteria",
        camping = "Camping store",
        candystore = "Candy store",
        cardealershipoffice = "Car dealership",
        carsupply = "Auto parts",
        church = "Church",
        classroom = "School",
        clothesstore = "Clothes store",
        conveniencestore = "Convenience store",
        cornerstore = "Corner store",
        dentist = "Dentist",
        departmentstore = "Department store",
        diner = "Diner",
        dinerkitchen = "Diner",
        donut_dining = "Donut shop",
        factorystorage = "Factory",
        firestation = "Fire station",
        fossoil = "Fossoil",
        furniturestore = "Furniture store",
        gardenstore = "Garden center",
        gas2go = "Gas 2 Go",
        gasstore = "Gas station",
        generalstore = "General store",
        giftstore = "Gift shop",
        gigamart = "Gigamart",
        grocers = "Grocer",
        grocery = "Grocery",
        grocerystorage = "Grocery",
        gunstore = "Gun store",
        gunstorestorage = "Gun store",
        gym = "Gym",
        hospitalhallway = "Hospital",
        hospitalroom = "Hospital",
        jewelrystore = "Jeweler",
        kennels = "Kennels",
        leatherclothesstore = "Leather store",
        library = "Library",
        liquorstore = "Liquor store",
        loggingfactory = "Lumber mill",
        mechanic = "Mechanic",
        medclinic = "Clinic",
        medical = "Clinic",
        medicaloffice = "Clinic",
        medicalstorage = "Clinic",
        motelreception = "Motel",
        motelroom = "Motel",
        motelroomoccupied = "Motel",
        movierental = "Video store",
        musicschool = "Music school",
        musicstore = "Music store",
        optometrist = "Optometrist",
        pawnshop = "Pawn shop",
        pharmacy = "Pharmacy",
        policehall = "Police station",
        policeoffice = "Police station",
        policestorage = "Police station",
        poststorage = "Post office",
        prisoncells = "Prison",
        rangerhall = "Ranger station",
        recreation = "Rec center",
        restaurant = "Restaurant",
        restaurantdining = "Restaurant",
        restaurantkitchen = "Restaurant",
        rollerrink = "Roller rink",
        security = "Security office",
        sewingstore = "Sewing store",
        shoestore = "Shoe store",
        spiffo_dining = "Spiffo's",
        sportstore = "Sports store",
        stripclub = "Strip club",
        theatre = "Theatre",
        toolstore = "Hardware store",
        toystore = "Toy store",
        westerndining = "Restaurant",
        zippeestore = "Zippee Market"
    }
}

local facings = {
    E = true,
    S = true,
    W = true,
    N = true
}

-- Reverse of `sprites`: our sprite -> facing. Rebuilt whenever a replacement
-- is added rather than on read, because it is read on every square load.
local ours = {}

local function rebuildOurs()
    ours = {}
    for facing, value in pairs(Core.phones.sprites) do
        if type(value) == "table" then
            for _, name in ipairs(value) do
                ours[name] = facing
            end
        else
            ours[value] = facing
        end
    end
end
rebuildOurs()

--- Make a vanilla sprite eligible for the swap. Facing is the way the tile
--- faces, which is what picks the replacement.
function Core.addPhoneTarget(sprite, facing)
    if type(sprite) ~= "string" or not facings[facing] then
        Core.logLn("addPhoneTarget needs a sprite name and one of E, S, W, N")
        return false
    end
    Core.phones.targets[sprite] = facing
    return true
end

--- Add a replacement for one facing. With `replace` true it becomes the only
--- one; otherwise it joins whatever is there and one is picked at random.
function Core.addPhoneSprite(facing, sprite, replace)
    if type(sprite) ~= "string" or not facings[facing] then
        Core.logLn("addPhoneSprite needs one of E, S, W, N and a sprite name")
        return false
    end
    local existing = Core.phones.sprites[facing]
    if replace or existing == nil then
        Core.phones.sprites[facing] = sprite
    elseif type(existing) == "table" then
        table.insert(existing, sprite)
    elseif existing ~= sprite then
        Core.phones.sprites[facing] = {existing, sprite}
    end
    rebuildOurs()
    -- A replacement added after boot is guarded like the rest. Before boot
    -- this finds no sprites loaded and does nothing, and the guards' own
    -- install catches it.
    if Core.hardenPhoneSprites then
        Core.hardenPhoneSprites()
    end
    return true
end

--- Offer a square as somewhere a phone may go. x, y, z is the PHONE's square
--- and `facing` which way it faces, so the character stands on the square in
--- front (Core.phoneFront): check both in game, as for a point's `phone`.
---
--- `chance` (1 to 100, default 100) is the percent chance it is drawn at all
--- when its turn comes. Below 100 a group of candidates can come up empty;
--- one that fails steps aside for the next in the draw.
---
--- `mods` (optional) is a list of mod ids: with one, the square is offered
--- only when at least one of them is active, and otherwise nothing is added
--- and this returns false. A world whose mods change is handled by the draw
--- as a candidate taken out or added late.
---
--- Safe from any hook that runs before the first square loads, and later too:
--- a candidate that turns up late takes its place in the pool when it does.
--- Adding the same square again replaces it and keeps its rank.
function Core.addPhoneCandidate(x, y, z, facing, chance, mods)
    if type(x) ~= "number" or type(y) ~= "number" or not facings[facing] then
        Core.logLn("addPhoneCandidate needs x, y, z and one of E, S, W, N")
        return false
    end
    if chance ~= nil and (type(chance) ~= "number" or chance < 1 or chance > 100) then
        Core.logLn("addPhoneCandidate's chance is a percent, 1 to 100")
        return false
    end
    local modsOk, modsWhy = Core.tools.checkMods(mods)
    if not modsOk then
        Core.logLn("addPhoneCandidate: " .. modsWhy)
        return false
    end
    if not Core.tools.anyModActive(mods) then
        return false
    end
    x, y, z = math.floor(x), math.floor(y), math.floor(z or 0)
    Core.phones.candidates[Core.phoneKey(x, y, z)] = {
        x = x,
        y = y,
        z = z,
        facing = facing,
        chance = chance or 100
    }
    Core.phones.candidatesVersion = Core.phones.candidatesVersion + 1
    return true
end

--- Offer a phone a MAP puts down: x, y, z is the vanilla phone's square and
--- `facing` its facing. The same pool as addPhoneCandidate, with two
--- differences: it goes up only by replacing a vanilla phone standing there
--- (a square without one is dropped for the world when it loads, so a map
--- that moved it, or a map that hides the cell, costs nothing), and its
--- chance is PhoneChance, or its zone's, rather than a fixed percent.
---
--- map_phones.lua offers every phone the lotpacks place, generated by
--- scripts/phones.pl. `mods` is as for addPhoneCandidate. An addPhoneCandidate
--- on the same square replaces it, whichever came first.
---
--- `room` (optional) is the room name the map gives the building the phone is
--- in or on, as the lotheader has it ("gasstore"). The phone is labelled with
--- its word in Core.phones.roomWords; a room with no word there, or none, is
--- labelled by its zone alone.
function Core.addMapPhone(x, y, z, facing, mods, room)
    if type(x) ~= "number" or type(y) ~= "number" or not facings[facing] then
        Core.logLn("addMapPhone needs x, y, z and one of E, S, W, N")
        return false
    end
    if not Core.tools.anyModActive(mods) then
        return false
    end
    x, y, z = math.floor(x), math.floor(y), math.floor(z or 0)
    local key = Core.phoneKey(x, y, z)
    local existing = Core.phones.candidates[key]
    if existing and not existing.replace then
        return false
    end
    Core.phones.candidates[key] = {
        x = x,
        y = y,
        z = z,
        facing = facing,
        replace = true,
        room = type(room) == "string" and room ~= "" and room or nil
    }
    Core.phones.candidatesVersion = Core.phones.candidatesVersion + 1
    return true
end

--- Every sprite of ours, as a set: name -> facing. A copy, so a caller
--- cannot edit the lookup behind rebuildOurs' back.
function Core.phoneSpriteSet()
    local out = {}
    for name, facing in pairs(ours) do
        out[name] = facing
    end
    return out
end

--- The facing of a vanilla sprite that is eligible for the swap, or nil.
function Core.phoneTargetFacing(spriteName)
    return spriteName and Core.phones.targets[spriteName] or nil
end

--- The facing of one of OUR phone sprites, or nil. Nil means "not a phone of
--- ours", which is the test the client menu and the square scan both use.
function Core.phoneFacing(spriteName)
    return spriteName and ours[spriteName] or nil
end

--- The replacement for a facing. `roll` picks from a list and is ZombRand in
--- game; it is a parameter so the spec can pick without one.
function Core.phoneSpriteFor(facing, roll)
    local value = Core.phones.sprites[facing]
    if type(value) == "table" then
        if #value == 0 then
            return nil
        end
        return value[(roll and roll(#value) or 0) + 1]
    end
    return value
end

--- The key of a square, "x_y_z", which is what a phone record is stored under.
--
-- It is also how the client tells a phone it knows from one it does not. A
-- known phone's point carries its phone's key in the points payload
-- (`phone`), and the client can build the key from a square it has loaded
-- without being told anything about phones it has not used. The key and not
-- the point id, because a point registered with a `phone` keeps its own id.
function Core.phoneKey(x, y, z)
    return tostring(x) .. "_" .. tostring(y) .. "_" .. tostring(z or 0)
end

--- The spawn point id of a swapped, kept or built phone on a square. A point
--- registered with a `phone` of its own has its own id instead.
function Core.phonePointId(x, y, z)
    return "phun.spawn.phone." .. Core.phoneKey(x, y, z)
end

--- Which phone should ring: the nearest spot within `range` that has one of
--- our phones standing on it now and whose square is not in `knownKeys`.
--
-- `spots` is key -> {x, y, z}, the squares the client has seen a phone on,
-- ours or vanilla. `standing(spot)` answers whether one of OURS is there
-- now, which is asked at ring time rather than trusted from load time: the
-- server's swap can land after the client loaded the square. It may also
-- return nil for "that square is gone", and the spot is then dropped.
function Core.phoneToRing(spots, knownKeys, px, py, range, standing)
    if not spots or not range or range <= 0 then
        return nil
    end
    local limit = range * range
    local best, bestDistance
    for key, spot in pairs(spots) do
        local dx, dy = spot.x - px, spot.y - py
        local distance = (dx * dx) + (dy * dy)
        if distance <= limit and (not bestDistance or distance < bestDistance) then
            local ours = standing(spot)
            if ours == nil then
                spots[key] = nil
            elseif ours and not knownKeys[Core.phoneKey(spot.x, spot.y, spot.z)] then
                best, bestDistance = spot, distance
            end
        end
    end
    return best
end

--- The square a character stands on to use a phone at x, y facing `facing`.
function Core.phoneFront(x, y, facing)
    local offset = Core.phones.front[facing] or {0, 0}
    return x + offset[1], y + offset[2]
end

--- The other way round: the square the phone stands on, for a character on
--- x, y using one facing `facing`.
function Core.phoneBehind(x, y, facing)
    local offset = Core.phones.front[facing] or {0, 0}
    return x - offset[1], y - offset[2]
end

return Core
