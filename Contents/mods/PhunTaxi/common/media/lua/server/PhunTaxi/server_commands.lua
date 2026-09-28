if isClient() then
    return
end
require "PhunSpawn/points"
require "PhunSpawn/tools"
local Core = PhunSpawn
local Unlocks = require "PhunSpawn/unlocks"
local Placement = require "PhunSpawn/placement"
local PhoneSwap = require "PhunSpawn/phone_swap"
local Store = require "PhunSpawn/store"
local Rides = require "PhunSpawn/rides"
local Building = require "PhunSpawn/building"
local Arrival = require "PhunSpawn/arrival"
local Commands = {}

-- ---------------------------------------------------------------------------
-- Server command handlers.
--
-- Returns a table; server_events.lua dispatches into it. Every handler takes
-- (player, args) and re-checks everything, because a command is an entry
-- point and never a gate: the client menu deciding not to offer something is
-- a convenience, not a permission.
-- ---------------------------------------------------------------------------

--- Everything the picker draws from, in one message.
--
-- One builder for every sender, so the flags cannot come to mean different
-- things depending on which handler answered. `canSpawn` is only ever a hint
-- for the button: the spawn handler asks Placement again rather than trusting
-- that the client still has it right.
local function sendPoints(player)
    Core.respond(player, Core.commands.points, {
        points = Unlocks.payloadFor(player),
        last = Unlocks.lastChoice(player),
        pending = Placement.isPending(player),
        canSpawn = Placement.canSpawn(player)
    })
end

-- Also the picker's "refresh", sent whenever it opens. Loading the cache
-- again is cheap and idempotent, and it is what makes a point found by the
-- timed sweep, which only announces itself, appear in the list.
--
-- And the server's first sight of a new character, so it is where one is put
-- in the arrival room: after the load, because where they fall back to is
-- read off their unlocks, and before the points go out, because a fallback
-- uses up the choice the payload reports.
Commands[Core.commands.playerSetup] = function(player, args)
    Unlocks.load(player)
    Arrival.admit(player)
    sendPoints(player)
end

--- "Wake me up here next time."
Commands[Core.commands.choose] = function(player, args)
    local id = args and args.id
    if not id or not Core.points[id] then
        Core.respond(player, Core.commands.notify, {
            text = "IGUI_PhunSpawn_NoSuchPoint"
        })
        return
    end
    if not Unlocks.has(player, id) then
        -- Refused rather than silently ignored. A client that got here has
        -- either a stale list or a modified one, and both cases deserve an
        -- answer the player can see.
        Core.respond(player, Core.commands.notify, {
            text = "IGUI_PhunSpawn_NotDiscovered"
        })
        return
    end

    Unlocks.setLastChoice(player, id)
    Core.respond(player, Core.commands.notify, {
        text = "IGUI_PhunSpawn_ChoiceSet",
        arg = Core.points[id].label
    })
end

--- "Put me at this point now."
--
-- The same two refusals as choose, then the one that matters: whether this
-- character may still choose at all. See placement.lua for why that is once,
-- for a new character, and never on demand.
--
-- The move itself is PhunInteriors.sendTo, and never a teleport of our own.
-- A new character is normally standing in the arrival room, and a bare
-- teleport out of a room leaves PhunInteriors believing they are still in
-- it: the occupancy, the lease, the leash and the client's "Step outside"
-- all stay behind. sendTo is a real exit with the destination replaced, and
-- it pushes zombies off the landing square once the player arrives. The
-- room is released, because nobody comes back to their arrival room.
Commands[Core.commands.spawn] = function(player, args)
    local id = args and args.id
    local point = id and Core.points[id]
    if not point then
        Core.respond(player, Core.commands.notify, {
            text = "IGUI_PhunSpawn_NoSuchPoint"
        })
        return
    end
    if not Unlocks.has(player, id) then
        Core.respond(player, Core.commands.notify, {
            text = "IGUI_PhunSpawn_NotDiscovered"
        })
        return
    end
    if not Placement.canSpawn(player) then
        Core.respond(player, Core.commands.notify, {
            text = "IGUI_PhunSpawn_AlreadyPlaced"
        })
        return
    end
    -- Never into somebody else's safehouse. Asked before the move rather
    -- than after, so the character simply stays where they are, with their
    -- choice still open, instead of arriving and being sent back.
    if Rides.safehouseBlocks(player, point.x, point.y) then
        Core.respond(player, Core.commands.notify, {
            text = "IGUI_PhunSpawn_TaxiSafehouse",
            arg = point.label
        })
        return
    end

    -- A hard dependency, so this is only ever missing when PhunInteriors is
    -- older than this mod. Said loudly: failing quietly here is a new
    -- character stuck in the arrival room with a button that does nothing.
    if not (PhunInteriors and PhunInteriors.sendTo) then
        Core.logLn("PhunInteriors.sendTo is missing; PhunInteriors is older than this version of PhunSpawn needs")
        Core.respond(player, Core.commands.notify, {
            text = "IGUI_PhunSpawn_CannotGoThere"
        })
        return
    end

    -- TODO: point.room is ignored. A point that wakes you inside a
    -- PhunInteriors room needs that room leased and the character put in it,
    -- which is not built.
    local ok, why = PhunInteriors.sendTo(player, {
        x = point.x,
        y = point.y,
        z = point.z
    }, "phunspawn", true)
    if not ok then
        -- Before anything is stamped, so a refused spawn leaves the choice
        -- open rather than using it up on a move that never happened.
        Core.logLn("spawn at " .. id .. " refused by PhunInteriors: " .. tostring(why))
        Core.respond(player, Core.commands.notify, {
            text = "IGUI_PhunSpawn_CannotGoThere"
        })
        return
    end

    Placement.markSpawned(player)
    Unlocks.setLastChoice(player, id)
    Core.respond(player, Core.commands.notify, {
        text = "IGUI_PhunSpawn_WokeUp",
        arg = point.label
    })
    triggerEvent(Core.events.OnSpawned, player, point)
    Core.debugLn(tostring(Core.playerKey(player)) .. " spawned at " .. id)
    -- So the picker, if it is still open anywhere, stops offering the button.
    sendPoints(player)
end

--- "Build a pay phone from this kit here." Everything is decided in
--- building.lua; a refusal leaves the kit where it was.
Commands[Core.commands.buildPoint] = function(player, args)
    local point, why, arg = Building.build(player, args)
    if not point then
        Core.respond(player, Core.commands.notify, {
            text = why,
            arg = arg
        })
        return
    end
    Core.respond(player, Core.commands.notify, {
        text = "IGUI_PhunSpawn_PhoneBuilt",
        arg = point.label
    })
    sendPoints(player)
end

Commands[Core.commands.takeDownPhone] = function(player, args)
    local ok, why = Building.takeDown(player, args)
    Core.respond(player, Core.commands.notify, {
        text = ok and "IGUI_PhunSpawn_PhoneTakenDown" or why
    })
    if ok then
        sendPoints(player)
    end
end

--- "Take me by taxi from this phone to there." See rides.lua.
Commands[Core.commands.taxi] = function(player, args)
    local point, why, arg = Rides.ride(player, args)
    if not point then
        Core.respond(player, Core.commands.notify, {
            text = why,
            arg = arg
        })
        return
    end
    Core.respond(player, Core.commands.notify, {
        text = "IGUI_PhunSpawn_TaxiArrived",
        arg = point.label
    })
end

--- "I am using the pay phone on this square."
--
-- Everything is decided in phone_swap.lua, which checks the phone against the
-- square and the square against where the player stands. Using a phone twice
-- is not a refusal, just nothing new to remember.
Commands[Core.commands.usePhone] = function(player, args)
    local point, granted = PhoneSwap.use(player, args)
    if not point then
        -- `granted` is the reason here, a translation key.
        Core.respond(player, Core.commands.notify, {
            text = granted
        })
        return
    end
    if granted then
        Core.respond(player, Core.commands.unlocked, {
            id = point.id,
            label = point.label,
            text = "IGUI_PhunSpawn_PhoneAnswered"
        })
        sendPoints(player)
    else
        Core.respond(player, Core.commands.notify, {
            text = "IGUI_PhunSpawn_PhoneKnown",
            arg = point.label
        })
    end
end

-- ---------------------------------------------------------------------------
-- The admin editor. Each handler checks admin rights itself: the context menu
-- only offering the editor to admins is a convenience, and these are entry
-- points anybody's client can send.
-- ---------------------------------------------------------------------------

local function sendAdminPoints(player)
    Core.respond(player, Core.commands.adminPoints, {
        points = Core.adminPayload()
    })
end

Commands[Core.commands.adminList] = function(player, args)
    if not Core.tools.isAdmin(player) then
        return
    end
    sendAdminPoints(player)
end

--- "Put me at this point."
--
-- Any registered point, known to this admin or not, and deliberately none of
-- what the spawn command does around the move: it grants nothing, sets no
-- last choice and stamps no placement. An admin checking a point is not
-- discovering it or choosing where to wake up, and a new admin character who
-- ports about before choosing must still have their choice.
--
-- The move is PhunInteriors.sendTo for the spawn command's reason. The room is
-- NOT released: an admin may be standing in a room of their own, and porting
-- out to look at something is no reason to lose it.
Commands[Core.commands.adminPort] = function(player, args)
    if not Core.tools.isAdmin(player) then
        return
    end
    local id = args and args.id
    local point = id and Core.points[id]
    if not point then
        Core.respond(player, Core.commands.notify, {
            text = "IGUI_PhunSpawn_NoSuchPoint"
        })
        return
    end
    if not (PhunInteriors and PhunInteriors.sendTo) then
        Core.logLn("PhunInteriors.sendTo is missing; PhunInteriors is older than this version of PhunSpawn needs")
        Core.respond(player, Core.commands.notify, {
            text = "IGUI_PhunSpawn_CannotGoThere"
        })
        return
    end
    local ok, why = PhunInteriors.sendTo(player, {
        x = point.x,
        y = point.y,
        z = point.z
    }, "phunspawn_admin", false)
    if not ok then
        Core.logLn("admin port to " .. id .. " refused by PhunInteriors: " .. tostring(why))
        Core.respond(player, Core.commands.notify, {
            text = "IGUI_PhunSpawn_CannotGoThere"
        })
        return
    end
    Core.respond(player, Core.commands.notify, {
        text = "IGUI_PhunSpawn_Ported",
        arg = point.label
    })
    Core.logLn(tostring(Core.playerKey(player)) .. " ported to " .. id)
end

--- "Call this point this."
--
-- The rename is saved to the store file, so it survives a wipe. The editor
-- gets its list again so the row shows what was stored, trimmed, rather than
-- what was typed. Players see the new name the next time their picker asks
-- for its list, which it does every time it opens.
Commands[Core.commands.adminRename] = function(player, args)
    if not Core.tools.isAdmin(player) then
        return
    end
    local id = args and args.id
    local point, why = Store.rename(id, args and args.label)
    if not point then
        Core.respond(player, Core.commands.notify, {
            text = why
        })
        return
    end
    Core.logLn(tostring(Core.playerKey(player)) .. " renamed " .. tostring(id) .. " to '" .. point.label .. "'")
    Core.respond(player, Core.commands.notify, {
        text = "IGUI_PhunSpawn_Renamed",
        arg = point.label
    })
    sendAdminPoints(player)
end

-- ---------------------------------------------------------------------------
-- Setting a world up: points and phones an admin saves to the store file, so
-- the next world after a wipe starts with them. Each answers with a notice
-- and, on success, a fresh editor list.
-- ---------------------------------------------------------------------------

local function refuse(player, why)
    Core.respond(player, Core.commands.notify, {
        text = why
    })
end

local function done(player, text, point)
    Core.respond(player, Core.commands.notify, {
        text = text,
        arg = point and point.label or nil
    })
    sendAdminPoints(player)
end

--- "Add a point on this square, called this."
--
-- The square comes from the client, which is fine for an admin: this is the
-- one command where the admin is saying where. It is found by exploring until
-- the editor says otherwise, the region is PhunZones' name for the square.
Commands[Core.commands.adminAddPoint] = function(player, args)
    if not Core.tools.isAdmin(player) then
        return
    end
    local x, y, z = tonumber(args and args.x), tonumber(args and args.y), tonumber(args and args.z) or 0
    if not x or not y then
        return refuse(player, "IGUI_PhunSpawn_NoSuchPoint")
    end
    local region = PhoneSwap.locate(x, y)
    local point, why = Store.addPoint(x, y, z, args.label, region)
    if not point then
        return refuse(player, why)
    end
    Core.logLn(tostring(Core.playerKey(player)) .. " added " .. point.id .. " '" .. point.label .. "'")
    done(player, "IGUI_PhunSpawn_PointAdded", point)
end

Commands[Core.commands.adminRemovePoint] = function(player, args)
    if not Core.tools.isAdmin(player) then
        return
    end
    local id = args and args.id
    local ok, why = Store.removePoint(id)
    if not ok then
        return refuse(player, why)
    end
    Core.logLn(tostring(Core.playerKey(player)) .. " removed " .. tostring(id))
    done(player, "IGUI_PhunSpawn_PointRemoved")
end

Commands[Core.commands.adminSetKind] = function(player, args)
    if not Core.tools.isAdmin(player) then
        return
    end
    local id = args and args.id
    local point, why = Store.setKind(id, args and args.discovery)
    if not point then
        return refuse(player, why)
    end
    Core.logLn(tostring(Core.playerKey(player)) .. " set " .. tostring(id) .. " to " .. point.discovery)
    done(player, "IGUI_PhunSpawn_KindSet", point)
end

--- "Keep this phone." By square from the context menu, or by point id from
--- the editor, which lists only phones that already have a record. With a
--- facing, "put a phone here facing this way, and keep it".
Commands[Core.commands.adminKeepPhone] = function(player, args)
    if not Core.tools.isAdmin(player) then
        return
    end
    local x, y, z = tonumber(args and args.x), tonumber(args and args.y), tonumber(args and args.z) or 0
    local key = PhoneSwap.keyOfPoint(args and args.id)
    local record = key and PhoneSwap.store()[key]
    if record then
        x, y, z = record.x, record.y, record.z or 0
    end
    if not x or not y then
        return refuse(player, "IGUI_PhunSpawn_NoPhoneHere")
    end
    -- A facing only from the context menu's "Add phone and spawn point
    -- here", and only for a square with no phone on it yet.
    local point, why = PhoneSwap.keep(x, y, z, args.facing)
    if not point then
        return refuse(player, why)
    end
    Core.logLn(tostring(Core.playerKey(player)) .. " kept the pay phone " .. point.id)
    done(player, "IGUI_PhunSpawn_PhoneKept", point)
end

Commands[Core.commands.adminReleasePhone] = function(player, args)
    if not Core.tools.isAdmin(player) then
        return
    end
    local key = PhoneSwap.keyOfPoint(args and args.id)
    local point, why = PhoneSwap.release(key)
    if not point then
        return refuse(player, why or "IGUI_PhunSpawn_NotKept")
    end
    Core.logLn(tostring(Core.playerKey(player)) .. " released the pay phone " .. point.id)
    done(player, "IGUI_PhunSpawn_PhoneReleased", point)
end

--- Admin actions, reachable from the console as PhunSpawn.admin(action, args).
--
-- Every one re-checks admin rights here rather than trusting the caller, and
-- the result goes back as lines for a log rather than as a structure, which
-- is why it has its own command.
Commands[Core.commands.admin] = function(player, args)
    if not Core.tools.isAdmin(player) then
        return
    end
    local action = args and args.action
    local result = {}

    if action == "list" then
        for _, point in ipairs(Core.sortedPoints()) do
            table.insert(result, string.format("%-44s %-16s %d,%d,%d  %s",
                point.id, tostring(point.region), point.x, point.y, point.z, point.discovery))
        end
        if #result == 0 then
            table.insert(result, "no points registered")
        end

    elseif action == "grant" then
        local target = args.username and Core.tools.getPlayerByUsername(args.username) or player
        if target and args.id and Unlocks.grant(target, args.id) then
            table.insert(result, "granted " .. tostring(args.id))
        else
            table.insert(result, "nothing granted")
        end

    elseif action == "reload" then
        -- For a hand edit of the store file made while the server runs.
        -- Without it the next change made in game writes over the edit.
        local problems = Store.reload()
        PhoneSwap.adopt()
        for key, record in pairs(PhoneSwap.store()) do
            PhoneSwap.registerRecord(key, record)
        end
        table.insert(result, "read " .. Store.FILE .. " again, " .. #problems .. " problem(s)")
        for _, complaint in ipairs(problems) do
            table.insert(result, "  " .. complaint)
        end
        table.insert(result, Core.describeRegistry())

    elseif action == "where" then
        table.insert(result, string.format("%d, %d, %d",
            player:getX(), player:getY(), player:getZ()))

    else
        table.insert(result, Core.describeRegistry())
    end

    Core.respond(player, Core.commands.adminResult, {result = result})
end

return Commands
