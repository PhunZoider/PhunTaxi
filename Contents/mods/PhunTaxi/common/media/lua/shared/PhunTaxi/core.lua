-- PhunSpawn
--
-- Spawn points that are earned rather than listed. A character starts knowing
-- the few the save is configured to give them and finds the rest by walking
-- the map or by building one, and a new character wakes up in a room rather
-- than on a kerb.
--
-- Standard Phun conventions, mirroring PhunInteriors and PhunCure2:
--   * everything hangs off this one global and nothing else,
--   * nothing may be hung off it under a name this table already declares,
--   * *_commands.lua returns a Commands table and *_events.lua dispatches
--     into it,
--   * server files open with `if isClient() then return end`, client files
--     with `if isServer() then return end`, and in SP both load,
--   * one code path for SP and MP, through Core.dispatch / Core.respond.
PhunSpawn = {
    name = "PhunSpawn",
    consts = {
        -- global ModData key, and the key every sub table hangs off
        modDataKey = "PhunSpawn",
        -- Where a PLAYER's unlocks live: Core.data[accountsKey][accountKey],
        -- in global ModData, as {unlocked = {pointId = true}, lastChoice}.
        --
        -- Per player and not per character, because unlocks exist to be
        -- spawned at and a character is only ever spawned once: dying makes a
        -- new character with fresh modData, so a list kept on the character
        -- would die with the one who earned it and reach nobody who could use
        -- it. The cost is that global_mod_data.bin is now what an afternoon of
        -- exploring rides on, where the character record used to be.
        accountsKey = "accounts",
        -- LEGACY. Where unlocks and the last choice lived when they were per
        -- character, on the player's modData. Read once per character, folded
        -- into the account and cleared; see unlocks.lua.
        unlockedKey = "PhunSpawn_unlocked",
        lastChoiceKey = "PhunSpawn_lastChoice",
        -- Whether this character has been placed yet, on the PLAYER. See
        -- server/placement.lua: nil is "not looked at", "pending" is a new
        -- character still choosing, and a number is when they were placed.
        -- Kept beside the unlocks for the same reason: a character who
        -- rejoins must not be offered a second free choice.
        spawnedKey = "PhunSpawn_spawned",
        -- Durable id of a point a player BUILT, written into the object's
        -- modData. Inside movableData rather than at the top level, because
        -- vanilla drops a top level key on pickup for some object classes and
        -- not others: see the pickup row in PhunInteriors' API table.
        objectIdKey = "PhunSpawn_pointId",
        -- Stamped on a vanilla pay phone once it has had its roll, win or
        -- lose, so it does not roll again every time its chunk loads. The
        -- same sentinel PhunMart puts on a vending machine.
        phoneRolledKey = "PhunSpawn_phoneRolled",
        -- On a phone a player built, the account key of who built it, so
        -- their client can offer to take it down. The server's record is the
        -- truth; this is only what the menu reads.
        phoneOwnerKey = "PhunSpawn_owner",
        -- The kit a player crafts and builds a phone from.
        phoneKitItem = "PhunSpawn.PayPhoneKit",
        -- The file an admin's work is kept in: points they added, phones
        -- they kept, and renames. In the game's Lua folder rather than the
        -- save, so it survives a wipe. See server/store.lua.
        storeFile = "PhunSpawn.json",
        -- What a point an admin added is registered under: this and its
        -- square, so two can never share one.
        customPrefix = "phun.spawn.custom.",
        -- The longest label the editor will store. A label is drawn in a
        -- list row and beside a map pin, and neither wraps.
        labelMax = 60
    },
    data = {},
    commands = {
        -- client -> server, on login: "tell me what I know about"
        playerSetup = "playerSetup",
        -- server -> client: the points this character may pick from
        points = "points",
        -- client -> server: "wake me up here next time"
        choose = "choose",
        -- client -> server: "put me at this point now". Carries a point id,
        -- which the server checks against the character's own unlocks and
        -- against whether they may still choose at all.
        spawn = "spawn",
        -- server -> client: "you just found one", so the client can say so
        unlocked = "unlocked",
        -- client -> server: "build a pay phone from this kit on this square,
        -- facing this way". Carries the square, the facing and the kit's
        -- item id; the server checks all three.
        buildPoint = "buildPoint",
        -- client -> server: "take down the phone I built on this square"
        takeDownPhone = "takeDownPhone",
        -- client -> server: "take me by taxi from the phone on this square to
        -- this point". Fast travel, for a fare; see server/taxi.lua.
        taxi = "taxi",
        -- client -> server: "I am using the pay phone on this square".
        -- Carries the phone's square, which the server checks against where
        -- the player stands and against its own list of swapped phones.
        usePhone = "usePhone",
        notify = "notify",
        admin = "admin",
        adminResult = "adminResult",
        -- The admin editor. Every one of these is re-checked for admin
        -- rights on the server; the menu hiding the editor is not a gate.
        -- client -> server: "send me every point there is"
        adminList = "adminList",
        -- server -> client: every registered point, with coordinates,
        -- whatever the requester has discovered
        adminPoints = "adminPoints",
        -- client -> server: "put me at this point". Any point, known or not,
        -- and it neither grants it nor uses up a new character's choice.
        adminPort = "adminPort",
        -- client -> server: "call this point this". An empty label, or the
        -- registered one, puts the registered label back.
        adminRename = "adminRename",
        -- client -> server: "add a point on this square, called this".
        -- Saved to the store file, so it survives a wipe.
        adminAddPoint = "adminAddPoint",
        -- client -> server: "take out a point I added"
        adminRemovePoint = "adminRemovePoint",
        -- client -> server: "change how a point I added is found"
        adminSetKind = "adminSetKind",
        -- client -> server: "keep the phone on this square after a wipe".
        -- A vanilla phone is swapped for ours first.
        adminKeepPhone = "adminKeepPhone",
        -- client -> server: "stop keeping it". The phone stays where it is,
        -- as an ordinary swapped phone.
        adminReleasePhone = "adminReleasePhone"
    },
    events = {
        -- Where third party mods register their own points, and where
        -- defaults.lua registers ours. Fired from Core.openRegistration.
        --
        -- Events rather than an "is PhunSpawn loaded" test on their side: if
        -- we are absent they never fire, so nobody has to guess how far
        -- through booting we are. What this does NOT buy is load order
        -- independence, which comes from the author hooking a vanilla event
        -- and registering from inside it. See README.md.
        OnRegisterPoints = "PhunSpawnOnRegisterPoints",
        OnReady = "PhunSpawnOnReady",
        -- A character unlocked a point. Carries (player, point).
        OnPointUnlocked = "PhunSpawnOnPointUnlocked",
        -- A character was spawned at one. Carries (player, point).
        OnSpawned = "PhunSpawnOnSpawned",
        -- CLIENT side: a fresh points payload has landed in Client.points.
        -- Carries the payload. The picker's list redraws on it, so a point
        -- found while the window is open shows up without reopening it.
        OnPointsReceived = "PhunSpawnOnPointsReceived",
        -- CLIENT side: the admin list has landed in Client.adminPoints.
        -- Separate from OnPointsReceived because the two payloads say
        -- different things: one is what this character knows, the other is
        -- everything there is.
        OnAdminPointsReceived = "PhunSpawnOnAdminPointsReceived"
    },
    -- Registry, populated by points.lua and by other mods on the register
    -- event.
    --   points:  id -> one spawn point
    --   regions: region name -> {pointId = true}, rebuilt lazily on first
    --            read after any registration, so a point that registers late
    --            is indexed without anybody having to sequence anything.
    points = {},
    regions = {},
    -- Server side only: account key -> {pointId = true}. A cache of the
    -- account record in global ModData, so a lookup does not reach into it
    -- on every tick. The record is the truth; this is the copy, and it is
    -- rebuilt on playerSetup.
    unlocked = {},
    -- What the store file says, server side: {points, phones, labels}.
    -- Loaded before anything registers, because a rename is read at
    -- registration. Written by server/store.lua, except `labels`, which
    -- Core.renamePoint edits for the store to save. Always empty on a
    -- client, which is told everything it needs in a payload.
    saved = {
        points = {},
        phones = {},
        labels = {}
    },
    settings = {},
    ui = {},
    modules = {}
}

local Core = PhunSpawn

Core.isLocal = not isClient() and not isServer() and not isCoopHost()

for _, event in pairs(Core.events) do
    if not Events[event] then
        LuaEventManager.AddEvent(event)
    end
end

--- Open registration.
--
-- Guarded, because in single player both server_events and client_events load
-- and each fires the boot sequence. Without the guard every handler, ours and
-- every third party's, runs twice. Mostly harmless here, since registerPoint
-- replaces rather than accumulates, but it logs a redefinition for every point
-- on every SP boot and turns a warning that ought to mean something into noise
-- nobody reads.
function Core.openRegistration()
    if Core.registrationFired then
        return false
    end
    Core.registrationFired = true
    triggerEvent(Core.events.OnRegisterPoints, Core)
    return true
end

-- Every constraint is a switch and the defaults are the balanced ones.
Core.defaults = {
    Debug = false,
    -- A new character wakes up in the spawn room rather than at the point
    -- itself. Needs PhunInteriors. With it absent this does nothing and the
    -- character is placed at the point, which is the honest fallback rather
    -- than a failure.
    UseSpawnRoom = true,
    -- How close you have to get before a point counts as found.
    DiscoveryRadius = 12,
    -- Whether undiscovered points are drawn greyed out or not at all. Shown
    -- is a map of somewhere to head for, hidden is a blank one.
    ShowUndiscovered = false,
    -- Whether a player may build a pay phone of their own from a kit.
    AllowBuiltPoints = true,
    -- How many phones one player may have standing at once. Zero means no
    -- limit.
    BuiltPointLimit = 5,
    -- No phone may be built within this many squares of any other phone of
    -- ours. Zero turns the spacing off.
    BuiltPhoneDistance = 50,
    -- How near, in squares, a phone has to be to count as found by walking
    -- up to it. Zero, the default, means only picking it up counts: the
    -- harder game. Separate from DiscoveryRadius, which is for places, where
    -- there is nothing to pick up and so no zero.
    PhoneDiscoverRadius = 0,
    -- A taxi from any known phone to any other, for a fare. Off by default:
    -- it is fast travel, and the free ride out of the spawn room is not.
    TaxiFastTravel = false,
    -- The fare, in cents of PhunMart's change, per square travelled, and
    -- the least any ride costs. Both zero is a free taxi, and needs no
    -- PhunMart.
    TaxiCentsPerSquare = 1,
    TaxiMinimumFare = 100,
    -- No taxi while a zombie is within this many squares. Zero turns the
    -- check off.
    TaxiZombieRadius = 6,
    -- Whether choosing a point costs the character anything on respawn.
    RespawnPenalty = false,
    -- Percent chance a vanilla pay phone is swapped for one of ours, rolled
    -- once per phone. Zero turns the swap off.
    PhoneChance = 50,
    -- No swapped phone within this many squares of another. Zero turns the
    -- spacing off.
    PhoneDistance = 500,
    -- A phone this player has never used rings now and then when they are
    -- near it, to draw them over. Decided and played client side; see
    -- client_phone.lua.
    PhoneRing = true,
    -- How near, in squares. 30 because that is as far as the sound carries.
    PhoneRingRange = 30
}

function Core.getOption(name, default)
    local opt = getSandboxOptions():getOptionByName(Core.name .. "." .. name)
    local val = opt and opt:getValue()
    if val == nil then
        return default
    end
    return val
end

function Core.refreshSettings()
    for name, default in pairs(Core.defaults) do
        Core.settings[name] = Core.getOption(name, default)
    end
    return Core.settings
end

function Core.debugLn(str)
    if Core.settings.Debug then
        print("[" .. Core.name .. "] " .. tostring(str))
    end
end

function Core.logLn(str)
    print("[" .. Core.name .. "] " .. tostring(str))
end

-- Client -> server. In single player there is no round trip, so call the
-- handler directly. This is what keeps SP and MP on one code path, and it is
-- the one rule in this family nothing may work around: a separate SP
-- implementation is two halves that drift.
function Core.dispatch(command, args)
    if Core.isLocal then
        local handlers = require "PhunSpawn/server_commands"
        local handler = handlers[command]
        if handler then
            handler(getPlayer(), args or {})
        end
    else
        sendClientCommand(Core.name, command, args or {})
    end
end

-- Server -> client, same deal in reverse.
function Core.respond(player, command, args)
    if Core.isLocal then
        local handlers = require "PhunSpawn/client_commands"
        local handler = handlers[command]
        if handler then
            handler(args or {})
        else
            Core.logLn("no local client handler for '" .. tostring(command) .. "'")
        end
    else
        sendServerCommand(player, Core.name, command, args or {})
    end
end

function Core.playerKey(player)
    if not player then
        return nil
    end
    return player:getUsername() or tostring(player:getOnlineID())
end

--- Who a player is across deaths: the key their unlocks are kept under.
--
-- The username on a server, which is the account and outlives every
-- character on it. In single player the username is not something to key on
-- (vanilla's own fishing falls back to the player number there for the same
-- reason), and the save is the only account there is, so it is the local
-- player slot: player 0 dying and coming back is still player 0.
function Core.accountKey(player)
    if not player then
        return nil
    end
    if Core.isLocal then
        return "local:" .. tostring(player:getPlayerNum())
    end
    return Core.playerKey(player)
end

function Core.now()
    return getGameTime():getWorldAgeHours()
end

Core.refreshSettings()

Events.EveryTenMinutes.Add(function()
    Core.refreshSettings()
end)

return Core
