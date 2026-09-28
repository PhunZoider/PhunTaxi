-- The admin editor's server half: renames, and the commands behind the
-- window.
--
-- The window is not tested here, for the picker's reason. What is tested is
-- what would fail quietly: a rename that does not survive the registration
-- running again on the next boot, an override that outlives being set back to
-- stock, and an admin port that hands out an unlock or uses up a new
-- character's one choice on the way past.
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
end

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

local sends = {}
PhunInteriors = {
    sendTo = function(player, destination, reason, release)
        table.insert(sends, {destination = destination, reason = reason, release = release})
        return true, 0
    end
}

local function register()
    Core.registerPoint("e.home", {label = "Home", region = "Muldraugh", x = 10, y = 20, z = 0,
        discovery = Core.discovery.start})
    Core.registerPoint("e.far", {label = "Far", region = "Riverside", x = 900, y = 950})
end

-- ---------------------------------------------------------------------------
-- A rename is an override, and survives the registration running again.
-- ---------------------------------------------------------------------------
reset()
register()
check("a point starts with its registered label", Core.points["e.far"].label, "Far")
check("rename returns the point", Core.renamePoint("e.far", "  The Marina  ") ~= nil, true)
check("and trims what was typed", Core.points["e.far"].label, "The Marina")
check("the override is in the store file's labels", Core.saved.labels["e.far"], "The Marina")
check("the registered label is kept beside it", Core.points["e.far"].shippedLabel, "Far")

-- The next boot: the registry is rebuilt from code, the store file is not.
Core.points = {}
register()
check("a rename survives registration running again", Core.points["e.far"].label, "The Marina")
check("while the registered label is still the code's", Core.points["e.far"].shippedLabel, "Far")

-- What players see comes out of the renamed point.
local ann = stubs.player("ann", 0)
Core.renamePoint("e.home", "Safehouse")
local homeRow
for _, row in ipairs(Unlocks.payloadFor(ann)) do
    if row.id == "e.home" then
        homeRow = row
    end
end
check("a player's payload carries the new label", homeRow and homeRow.label, "Safehouse")

-- ---------------------------------------------------------------------------
-- Back to stock removes the override rather than storing a copy of it.
-- ---------------------------------------------------------------------------
Core.renamePoint("e.far", "Far")
check("renaming to the registered label restores it", Core.points["e.far"].label, "Far")
check("and stores nothing", Core.saved.labels["e.far"], nil)
Core.renamePoint("e.home", "")
check("an empty label restores it too", Core.points["e.home"].label, "Home")
check("and stores nothing either", Core.saved.labels["e.home"], nil)

local point, why = Core.renamePoint("e.far", string.rep("x", Core.consts.labelMax + 1))
check("an over long label is refused", point, nil)
check("with a reason", why, "IGUI_PhunTaxi_LabelTooLong")
check("and changes nothing", Core.points["e.far"].label, "Far")
point, why = Core.renamePoint("e.nowhere", "Somewhere")
check("a point that does not exist cannot be renamed", why, "IGUI_PhunTaxi_NoSuchPoint")

-- ---------------------------------------------------------------------------
-- The admin payload is every point, with coordinates, found or not.
-- ---------------------------------------------------------------------------
Core.renamePoint("e.far", "The Marina")
local all = Core.adminPayload()
check("every point is listed", #all, 2)
local far
for _, row in ipairs(all) do
    if row.id == "e.far" then
        far = row
    end
end
check("an undiscovered point still has its x", far and far.x, 900)
check("a renamed point says so", far and far.renamed, true)
check("and carries the label to reset to", far and far.shippedLabel, "Far")

-- ---------------------------------------------------------------------------
-- The commands. Nobody but an admin gets an answer.
-- ---------------------------------------------------------------------------

-- A server, so tools.isAdmin asks the player rather than waving SP through.
Core.isLocal = false
local nobody = stubs.player("nobody", 400)
local boss = stubs.player("boss", 0)
boss.getAccessLevel = function()
    return "admin"
end

sent, sends = {}, {}
Commands[Core.commands.adminList](nobody, {})
Commands[Core.commands.adminPort](nobody, {id = "e.far"})
Commands[Core.commands.adminRename](nobody, {id = "e.far", label = "Mine"})
check("a player gets no list", lastSent(Core.commands.adminPoints), nil)
check("and is not moved", #sends, 0)
check("and renames nothing", Core.points["e.far"].label, "The Marina")

Commands[Core.commands.adminList](boss, {})
check("an admin gets every point", #lastSent(Core.commands.adminPoints).points, 2)

-- A new admin character, still choosing, ports to a point they have not
-- found. The port is all that happens.
check("the admin starts out choosing", Placement.isPending(boss), true)
Commands[Core.commands.adminPort](boss, {id = "e.far"})
check("an admin port goes through PhunInteriors", #sends, 1)
check("to the point's square", sends[1] and sends[1].destination.y, 950)
check("without giving up any room they hold", sends[1] and sends[1].release, false)
check("and says where", lastSent(Core.commands.notify).text, "IGUI_PhunTaxi_Ported")
check("it does not unlock the point", Unlocks.has(boss, "e.far"), false)
check("or use up the choice", Placement.isPending(boss), true)
check("or become the last choice", Unlocks.lastChoice(boss), nil)

sent = {}
Commands[Core.commands.adminPort](boss, {id = "e.nowhere"})
check("a port to nowhere is refused", #sends, 1)
check("and says so", lastSent(Core.commands.notify).text, "IGUI_PhunTaxi_NoSuchPoint")

sent = {}
Commands[Core.commands.adminRename](boss, {id = "e.home", label = "Bunker"})
check("an admin rename is stored", Core.points["e.home"].label, "Bunker")
check("and the editor gets its list again", lastSent(Core.commands.adminPoints) ~= nil, true)

sent = {}
Commands[Core.commands.adminRename](boss, {id = "e.home", label = {}})
check("a label that is not a string is refused", lastSent(Core.commands.notify).text, "IGUI_PhunTaxi_BadLabel")
check("and changes nothing", Core.points["e.home"].label, "Bunker")

Core.isLocal = true
os.exit(report.finish("editor") > 0 and 1 or 0)
