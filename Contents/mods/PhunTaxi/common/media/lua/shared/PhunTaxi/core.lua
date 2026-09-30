-- PhunTaxi
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
PhunTaxi = {
    name = "PhunTaxi",
    consts = {
        -- global ModData key, and the key every sub table hangs off
        modDataKey = "PhunTaxi",
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
        unlockedKey = "PhunTaxi_unlocked",
        lastChoiceKey = "PhunTaxi_lastChoice",
        -- SINGLE PLAYER ONLY. Whether this character has been placed yet, on
        -- the PLAYER. See server/placement.lua: nil is "not looked at",
        -- "pending" is a new character still choosing, and a number is when
        -- they were placed. On a server nothing is stored: standing in
        -- `garage` is pending.
        spawnedKey = "PhunTaxi_spawned",
        -- The Taxi Garage, cell 87,49, inclusive at both ends. Standing in it
        -- is what makes a character's ride free (server/placement.lua), and
        -- it is the PhunZones zone (zones.lua).
        garage = {
            x1 = 22272,
            y1 = 12544,
            x2 = 22527,
            y2 = 12799
        },
        -- Durable id of a point a player BUILT, written into the object's
        -- modData. Inside movableData rather than at the top level, because
        -- vanilla drops a top level key on pickup for some object classes and
        -- not others: see the pickup row in PhunInteriors' API table.
        objectIdKey = "PhunTaxi_pointId",
        -- On a phone a player built, the account key of who built it, so
        -- their client can offer to take it down. The server's record is the
        -- truth; this is only what the menu reads.
        phoneOwnerKey = "PhunTaxi_owner",
        -- The kit a player crafts and builds a phone from.
        phoneKitItem = "PhunTaxi.PayPhoneKit",
        -- The file an admin's work is kept in: points they added, phones
        -- they kept, and renames. In the game's Lua folder rather than the
        -- save, so it survives a wipe. See server/store.lua.
        storeFile = "PhunTaxi.json",
        -- What a point an admin added is registered under: this and its
        -- square, so two can never share one.
        customPrefix = "phun.spawn.custom.",
        -- The PhunZones fields a zone overrides PhoneChance and PhoneDistance
        -- with, inside it. Added to PhunZones' editor by zones.lua and read
        -- by phone_swap.lua; unset on a zone means the sandbox value.
        zoneChanceField = "phoneChance",
        zoneDistanceField = "phoneDistance",
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
        -- server -> every client: "one of ours just went up on this square".
        -- A client notes phones for the ring as their squares load, and a
        -- phone put up on an empty square arrives after that, so without
        -- this it is never noted and never rings.
        phoneUp = "phoneUp",
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
        -- client -> server: "take this point out". A point an admin added
        -- goes from the store file; any other point, shipped or a third
        -- party's, is tombstoned there, so it stays gone after a reboot.
        adminRemovePoint = "adminRemovePoint",
        -- client -> server: "take the tombstone off this point"
        adminRestorePoint = "adminRestorePoint",
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
        -- Events rather than an "is PhunTaxi loaded" test on their side: if
        -- we are absent they never fire, so nobody has to guess how far
        -- through booting we are. What this does NOT buy is load order
        -- independence, which comes from the author hooking a vanilla event
        -- and registering from inside it. See README.md.
        OnRegisterPoints = "PhunTaxiOnRegisterPoints",
        OnReady = "PhunTaxiOnReady",
        -- A character unlocked a point. Carries (player, point).
        OnPointUnlocked = "PhunTaxiOnPointUnlocked",
        -- A character was spawned at one. Carries (player, point).
        OnSpawned = "PhunTaxiOnSpawned",
        -- CLIENT side: a fresh points payload has landed in Client.points.
        -- Carries the payload. The picker's list redraws on it, so a point
        -- found while the window is open shows up without reopening it.
        OnPointsReceived = "PhunTaxiOnPointsReceived",
        -- CLIENT side: the admin list has landed in Client.adminPoints.
        -- Separate from OnPointsReceived because the two payloads say
        -- different things: one is what this character knows, the other is
        -- everything there is.
        OnAdminPointsReceived = "PhunTaxiOnAdminPointsReceived"
    },
    -- Registry, populated by points.lua and by other mods on the register
    -- event.
    --   points:  id -> one spawn point
    --   regions: region name -> {pointId = true}, rebuilt lazily on first
    --            read after any registration, so a point that registers late
    --            is indexed without anybody having to sequence anything.
    points = {},
    regions = {},
    --   registryVersion: counts every change to the registry, for a reader
    --            too hot to rebuild on every call, such as the phone sync
    --            that LoadGridsquare asks before every square.
    registryVersion = 0,
    --   deleted: id -> a point that registered while tombstoned. Never read
    --            as a point: it is here for the editor to show and for
    --            Restore to put back. See Core.deletePoint.
    deleted = {},
    -- Server side only: account key -> {pointId = true}. A cache of the
    -- account record in global ModData, so a lookup does not reach into it
    -- on every tick. The record is the truth; this is the copy, and it is
    -- rebuilt on playerSetup.
    unlocked = {},
    -- The shipped pay phones: a list of entries in the store file's own
    -- shape (a phone, or an override carrying only a label), filled by
    -- defaults.lua and by anybody else before OnInitGlobalModData. Shared, so
    -- every side has it, but only the server reads it: Store.load merges it
    -- under the store file, which overrides it. See server/store.lua.
    shipped = {},
    -- What the store file says, server side: {points, phones, labels,
    -- deleted, released}, taken apart from the file's one list of entries by
    -- Store.sanitise, with the shipped phones merged into `phones` unless
    -- the file overrides or releases them (`released`: key -> the shipped
    -- phone let go). Loaded before anything registers, because a rename and
    -- a tombstone are read at registration. Written by server/store.lua,
    -- except `labels` and `deleted`, which Core.renamePoint and
    -- Core.deletePoint edit for the store to save. Always empty on a client,
    -- which is told everything it needs in a payload.
    saved = {
        points = {},
        phones = {},
        labels = {},
        deleted = {},
        released = {}
    },
    settings = {},
    ui = {},
    modules = {}
}

local Core = PhunTaxi

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
    -- A new character wakes up in the spawn room and leaves by taxi. Off,
    -- or with no room free, they are placed at their fallback point
    -- instead (server/arrival.lua).
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
    -- Percent chance a map's pay phone goes live, against its rank's roll,
    -- which is fixed per world (server/phone_swap.lua). Zero leaves only the
    -- extra spots, which carry their own chance.
    PhoneChance = 35,
    -- No live phone within this many squares of another. Zero turns the
    -- spacing off.
    PhoneDistance = 300,
    -- A phone this player has never used rings, once a session, when they are
    -- near it, to draw them over. Decided and played client side; see
    -- client_phone.lua.
    PhoneRing = true,
    -- How near, in squares. 30 because that is as far as the sound carries.
    PhoneRingRange = 30,
    -- How long it rings, in real seconds: see Core.phones.ringSound.
    PhoneRingSeconds = 30
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
        local handlers = require "PhunTaxi/server_commands"
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
        local handlers = require "PhunTaxi/client_commands"
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

--- Server -> every client. In single player that is the one local client.
function Core.broadcast(command, args)
    if Core.isLocal then
        Core.respond(nil, command, args)
    else
        sendServerCommand(Core.name, command, args or {})
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
