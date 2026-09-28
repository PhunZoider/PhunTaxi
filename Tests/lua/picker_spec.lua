-- What the picker draws from and what its button is allowed to do.
--
-- The window itself is not tested here and cannot be: it is UIWorldMap and
-- ISScrollingListBox, and a stub of either would be testing the stub. What is
-- tested is the two pure halves underneath it, which are also the two that
-- would fail quietly: the grouping that decides which city a point is listed
-- under and where the map zooms, and the rule that makes the spawn button a
-- once only choice rather than fast travel.
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
local Commands = require "PhunTaxi/server_commands"
local report = stubs.reporter()
local check = report.check

local function reset()
    Core.points = {}
    Core.regions = {}
    Core.unlocked = {}
    Core.data = {}
    Core.saved = {points = {}, phones = {}, labels = {}}
    Core.indexesBuilt = false
    -- The picker's own flow, with nobody put in an arrival room first:
    -- playerSetup would otherwise place a new character at a fallback point
    -- before the button is ever pressed. arrival_spec.lua covers that.
    Core.settings.UseSpawnRoom = false
end

-- Every response the server sends, in order, instead of a client.
local sent = {}
Core.respond = function(player, command, args)
    table.insert(sent, {
        command = command,
        args = args
    })
end
local function lastSent(command)
    for i = #sent, 1, -1 do
        if sent[i].command == command then
            return sent[i].args
        end
    end
    return nil
end

-- PhunInteriors, standing in. The spawn is sendTo's job, so what matters here
-- is that it is asked, with what, and that a refusal uses nothing up.
local sends = {}
local refuseSends = false
PhunInteriors = {
    sendTo = function(player, destination, reason, release)
        if refuseSends then
            return false, "refused for the test"
        end
        table.insert(sends, {destination = destination, reason = reason, release = release})
        return true, 0
    end
}

-- ---------------------------------------------------------------------------
-- Grouping. Cities in name order with the unnamed one last, points in payload
-- order, and bounds over the KNOWN points only.
-- ---------------------------------------------------------------------------
local groups = Core.groupByRegion({
    {id = "w1", label = "Motel", region = "West Point", known = true, x = 100, y = 200},
    {id = "m1", label = "Warehouse", region = "Muldraugh", known = true, x = 10, y = 20},
    {id = "x1", label = "Shack", known = true, x = 5, y = 5},
    {id = "w2", label = "School", region = "West Point", known = true, x = 140, y = 150},
    {id = "w3", label = "Church", region = "West Point", known = false},
    {id = "r1", label = "Marina", region = "riverside", known = false}
})
check("one group per region", #groups, 4)
check("sorted by name", groups[1].name, "Muldraugh")
check("case insensitively", groups[2].name, "riverside")
check("then the next", groups[3].name, "West Point")
check("with the unnamed region last", groups[4].name, "")

local west = groups[3]
check("every point is listed", west.total, 3)
check("but only the found ones count as known", west.known, 2)
check("points keep the payload's order", west.points[2].id, "w2")
check("bounds take the smallest x", west.bounds.x1, 100)
check("and the smallest y", west.bounds.y1, 150)
check("and the largest x", west.bounds.x2, 140)
check("and the largest y", west.bounds.y2, 200)

-- A region of nothing but undiscovered points still gets a row, because that
-- is what ShowUndiscovered is for, and it has nowhere to zoom to.
check("an all unknown region is listed", groups[2].total, 1)
check("and has no bounds", groups[2].bounds, nil)
check("a nil payload groups to nothing", #Core.groupByRegion(nil), 0)

-- ---------------------------------------------------------------------------
-- New or established, decided once and stamped.
-- ---------------------------------------------------------------------------
reset()
local newbie = stubs.player("newbie", 0)
local veteran = stubs.player("veteran", 400)
check("a fresh character is pending", Placement.isPending(newbie), true)
check("an established one is not", Placement.isPending(veteran), false)
check("and is stamped as placed before we saw it", veteran:getModData()[Core.consts.spawnedKey], 0)

-- Decided once: a character who dawdles past the hour is still choosing.
local dawdler = stubs.player("dawdler", 0)
Placement.state(dawdler)
local lateDawdler = {
    getModData = dawdler.getModData,
    getHoursSurvived = function()
        return 5
    end
}
check("a pending character stays pending as time passes", Placement.isPending(lateDawdler), true)

-- ---------------------------------------------------------------------------
-- The spawn command. Every refusal is answered, and a spawn happens once.
-- ---------------------------------------------------------------------------
reset()
Core.registerPoint("s.home", {label = "Home", region = "Muldraugh", x = 10, y = 20, z = 0,
    discovery = Core.discovery.start})
Core.registerPoint("s.far", {label = "Far", region = "Riverside", x = 900, y = 900})

-- getDebug is not defined under the stubs, so single player here is "not in
-- debug mode", which is the case that must refuse a second spawn.
local ann = stubs.player("ann", 0)
Commands[Core.commands.playerSetup](ann, {})
local setup = lastSent(Core.commands.points)
check("setup tells a new character they are pending", setup.pending, true)
check("and that the button would work", setup.canSpawn, true)

sent = {}
Commands[Core.commands.spawn](ann, {id = "s.far"})
check("an undiscovered point is refused", #sends, 0)
check("and the refusal is said", lastSent(Core.commands.notify).text, "IGUI_PhunTaxi_NotDiscovered")

sent = {}
Commands[Core.commands.spawn](ann, {id = "s.nowhere"})
check("a point that does not exist is refused", lastSent(Core.commands.notify).text, "IGUI_PhunTaxi_NoSuchPoint")

-- PhunInteriors saying no, eg a square outside this world. The choice must
-- survive it: using it up on a move that never happened strands a new
-- character in the arrival room for good.
sent = {}
refuseSends = true
Commands[Core.commands.spawn](ann, {id = "s.home"})
refuseSends = false
check("a refused move is said", lastSent(Core.commands.notify).text, "IGUI_PhunTaxi_CannotGoThere")
check("and leaves the character still choosing", Placement.isPending(ann), true)

sent = {}
Commands[Core.commands.spawn](ann, {id = "s.home"})
local send = sends[#sends]
check("a known point goes through PhunInteriors", #sends, 1)
check("to the point's own square", send and send.destination.x, 10)
check("releasing the arrival room", send and send.release, true)
check("the character is no longer pending", Placement.isPending(ann), false)
check("the choice is remembered", Unlocks.lastChoice(ann), "s.home")
check("and the fresh payload withdraws the button", lastSent(Core.commands.points).canSpawn, false)

sent = {}
Commands[Core.commands.spawn](ann, {id = "s.home"})
check("a second spawn is refused", #sends, 1)
check("and says why", lastSent(Core.commands.notify).text, "IGUI_PhunTaxi_AlreadyPlaced")

-- An established character never had the choice.
local vic = stubs.player("vic", 400)
sent = {}
Commands[Core.commands.spawn](vic, {id = "s.home"})
check("an established character cannot spawn", #sends, 1)

os.exit(report.finish("picker") > 0 and 1 or 0)
