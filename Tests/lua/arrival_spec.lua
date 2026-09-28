-- The arrival room: who is put in it, what PhunInteriors is asked for, where
-- a character goes when there is no room, and the vanilla spawn regions
-- collapsing to one.
--
-- PhunInteriors.enterRoom is faked. Whether a slot is free, shared or
-- refused is its answer, and what is tested here is what we do with each.
local ROOT = os.getenv("PS_ROOT") or "."
local stubs = dofile(ROOT .. "/Tests/lua/stubs.lua")
stubs.install(ROOT)

require "PhunTaxi/core"
require "PhunTaxi/points"
local Core = PhunTaxi
Core.logLn = function()
end
Core.debugLn = function()
end

local Unlocks = require "PhunTaxi/unlocks"
local Placement = require "PhunTaxi/placement"
local Arrival = require "PhunTaxi/arrival"
local Commands = require "PhunTaxi/server_commands"
-- Responses go nowhere. In SP Core.respond calls the client handlers, which
-- need a game; what is said is not what is tested here.
Core.respond = function()
end
local report = stubs.reporter()
local check = report.check

local enters, sends
local enterOk, enterWhy = true, "phun.spawn.arrival#0"
local sendOk = true

local function reset()
    Core.points = {}
    Core.regions = {}
    Core.unlocked = {}
    Core.indexesBuilt = false
    Core.data = {}
    Core.settings.UseSpawnRoom = true
    enters, sends = {}, {}
    enterOk, enterWhy, sendOk = true, "phun.spawn.arrival#0", true
    PhunInteriors = {
        enterRoom = function(player, roomId, opts)
            table.insert(enters, {roomId = roomId, opts = opts})
            return enterOk, enterWhy
        end,
        sendTo = function(player, destination, reason, release)
            table.insert(sends, {destination = destination, reason = reason, release = release})
            return sendOk, sendOk and 0 or "no"
        end
    }
    Arrival.landing = nil
    Core.registerPoint("b.start", {label = "B", x = 200, y = 200, discovery = "start"})
    Core.registerPoint("a.start", {label = "A", x = 100, y = 100, discovery = "start"})
    Core.registerPoint("c.explore", {label = "C", x = 300, y = 300})
end

-- The admitted memo is per player key and lasts the session, as it does in
-- game, so every case below uses a name of its own.

-- ---------------------------------------------------------------------------
-- Who is admitted.
-- ---------------------------------------------------------------------------
reset()
local fresh = stubs.player("fresh", 0)
check("a new character is put in the room", Arrival.admit(fresh), "room")
check("the arrival room is asked for", enters[1] and enters[1].roomId, Core.roomIds.arrival)
check("shared when full", enters[1] and enters[1].opts.share, true)
check("with no walk out exit", enters[1] and enters[1].opts.exit, false)
check("rescue goes to a start point, lowest id first", enters[1] and enters[1].opts.returnTo.x, 100)
check("and they are still choosing", Placement.isPending(fresh), true)
check("nobody is moved by us", #sends, 0)

local _, why = Arrival.admit(fresh)
check("asked once a session", why, "admitted")
check("so PhunInteriors is not asked again", #enters, 1)

reset()
local old = stubs.player("old", 50)
_, why = Arrival.admit(old)
check("an established character is left alone", why, "placed")
check("without asking for a room", #enters, 0)

reset()
Core.settings.UseSpawnRoom = false
_, why = Arrival.admit(stubs.player("off", 0))
check("the option off admits nobody", why, "off")
check("and asks for nothing", #enters, 0)

reset()
local chose = stubs.player("chose", 0)
Unlocks.grant(chose, "c.explore")
Unlocks.setLastChoice(chose, "c.explore")
Arrival.admit(chose)
check("rescue goes to the last choice when it is known", enters[1] and enters[1].opts.returnTo.x, 300)

-- ---------------------------------------------------------------------------
-- No room.
-- ---------------------------------------------------------------------------
reset()
enterOk, enterWhy = false, "no slot"
local refused = stubs.player("refused", 0)
check("refused a room, they fall back", Arrival.admit(refused), "fallback")
check("to a start point they know", sends[1] and sends[1].destination.x, 100)
check("releasing any room", sends[1] and sends[1].release, true)
check("which uses up their choice", Placement.isPending(refused), false)
check("and is their last choice", Unlocks.lastChoice(refused), "a.start")

reset()
PhunInteriors.enterRoom = nil
check("an older PhunInteriors falls back too", Arrival.admit(stubs.player("older", 0)), "fallback")

reset()
enterOk, sendOk = false, false
local stuck = stubs.player("stuck", 0)
local placed = Arrival.admit(stuck)
check("nowhere at all leaves them be", placed, nil)
check("still choosing", Placement.isPending(stuck), true)
enterOk = true
check("and the next setup tries again", Arrival.admit(stuck), "room")

-- ---------------------------------------------------------------------------
-- Through the command, which is where the game calls it.
-- ---------------------------------------------------------------------------
reset()
Commands[Core.commands.playerSetup](stubs.player("setup", 0), {})
check("playerSetup admits a new character", #enters, 1)

-- ---------------------------------------------------------------------------
-- The vanilla regions.
-- ---------------------------------------------------------------------------
reset()
local regions = {{name = "Muldraugh"}, {name = "Riverside"}}
check("no landing square leaves the regions alone", Arrival.collapseRegions(regions), false)
check("both still there", #regions, 2)

Arrival.landing = {x = 22000, y = 12500, z = 0}
check("a landing square collapses them", Arrival.collapseRegions(regions), true)
check("to one, so the selector skips itself", #regions, 1)
check("in place", regions[1].name, "PhunTaxi")
check("at the landing square", regions[1].points.unemployed[1].posX, 22000)

regions = {{name = "Muldraugh"}, {name = "Riverside"}}
-- Read from the sandbox option itself, not the cache, which may still be
-- empty when the server builds its regions.
local realOptions = getSandboxOptions
getSandboxOptions = function()
    return {getOptionByName = function(_, name)
        if name == "PhunTaxi.UseSpawnRoom" then
            return {getValue = function() return false end}
        end
        return nil
    end}
end
check("the option off leaves them alone", Arrival.collapseRegions(regions), false)
getSandboxOptions = realOptions
check("both still there", #regions, 2)

os.exit(report.finish("arrival") > 0 and 1 or 0)
