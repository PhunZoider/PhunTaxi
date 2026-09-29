-- The store file: what an admin set up, and what survives a wipe.
--
-- A wipe here is Core.data, Core.points and the unlock cache emptied while
-- stubs.files is left alone, which is exactly the difference between the save
-- and the Lua folder. What is tested is what would fail quietly: something
-- saved that does not come back, a typo in a hand edit that costs the whole
-- file, a kept phone forgotten because its square loaded without it, and a
-- change that says it saved when the file would not write.
local ROOT = os.getenv("PS_ROOT") or "."
local stubs = dofile(ROOT .. "/Tests/lua/stubs.lua")
stubs.install(ROOT)

require "PhunTaxi/core"
require "PhunTaxi/points"
require "PhunTaxi/phones"
local Core = PhunTaxi
Core.logLn = function()
end
Core.debugLn = function()
end

local Unlocks = require "PhunTaxi/unlocks"
local PhoneSwap = require "PhunTaxi/phone_swap"
local Store = require "PhunTaxi/store"
local Commands = require "PhunTaxi/server_commands"
local json = require "PhunInteriors/json"
local report = stubs.reporter()
local check = report.check

local FILE = Core.consts.storeFile

local function wipe()
    Core.points = {}
    Core.deleted = {}
    Core.regions = {}
    Core.unlocked = {}
    Core.indexesBuilt = false
    Core.data = {}
    Core.saved = {points = {}, phones = {}, labels = {}, deleted = {}}
    Store.unreadable = false
    Core.settings.PhoneChance = 50
    Core.settings.PhoneDistance = 500
    PhunZones = nil
end

-- A boot, in server_events' order.
local function boot(shipped)
    Store.load()
    if shipped then
        shipped()
    end
    Store.registerAll()
    PhoneSwap.start()
end

local function fileDoc()
    return json.decode(stubs.files[FILE] or "")
end

local function shipped()
    Core.registerPoint("phun.spawn.test.home", {label = "Home", x = 10, y = 20, discovery = Core.discovery.start})
end

-- ---------------------------------------------------------------------------
-- No file is nothing saved, and nothing is written just by booting.
-- ---------------------------------------------------------------------------
stubs.files = {}
wipe()
boot(shipped)
check("no file boots", Core.points["phun.spawn.test.home"] ~= nil, true)
check("and does not create one", stubs.files[FILE], nil)
check("the shipped point is not saved", Core.points["phun.spawn.test.home"].saved, false)

-- ---------------------------------------------------------------------------
-- A point added in game comes back after a wipe.
-- ---------------------------------------------------------------------------
local point, why = Store.addPoint(1234.7, 5678.2, 0, "  The Gas Station ", "Muldraugh")
check("add returns the point", point and point.id, "phun.spawn.custom.1234_5678_0")
check("on the whole square", point and (point.x .. "," .. point.y), "1234,5678")
check("trimmed", point and point.label, "The Gas Station")
check("found by exploring", point and point.discovery, "explore")
check("and marked saved", point and point.saved, true)
check("the file is written", fileDoc() ~= nil, true)
check("with the point in it", fileDoc().points["phun.spawn.custom.1234_5678_0"].label, "The Gas Station")
check("and a version", fileDoc().version, 1)

point, why = Store.addPoint(1234, 5678, 0, "Again")
check("a second point on the square is refused", why, "IGUI_PhunTaxi_PointHere")
point, why = Store.addPoint(1, 1, 0, "   ")
check("a blank name is refused", why, "IGUI_PhunTaxi_BadLabel")
point, why = Store.addPoint(1, 1, 0, string.rep("x", Core.consts.labelMax + 1))
check("an over long name is refused", why, "IGUI_PhunTaxi_LabelTooLong")

Store.rename("phun.spawn.test.home", "Safehouse")
check("a rename is in the file", fileDoc().labels["phun.spawn.test.home"], "Safehouse")

wipe()
boot(shipped)
local back = Core.points["phun.spawn.custom.1234_5678_0"]
check("after a wipe the added point is back", back ~= nil, true)
check("with its name", back and back.label, "The Gas Station")
check("and region", back and back.region, "Muldraugh")
check("the rename survived the wipe too", Core.points["phun.spawn.test.home"].label, "Safehouse")

-- ---------------------------------------------------------------------------
-- Kind, and a start point reaching a new character.
-- ---------------------------------------------------------------------------
point, why = Store.setKind("phun.spawn.custom.1234_5678_0", Core.discovery.used)
check("used is refused for a point with no phone", why, "IGUI_PhunTaxi_BadKind")
point, why = Store.setKind("phun.spawn.test.home", Core.discovery.explore)
check("a shipped point's kind is not the file's to change", why, "IGUI_PhunTaxi_NotSavedPoint")
point = Store.setKind("phun.spawn.custom.1234_5678_0", Core.discovery.start)
check("start is taken", point and point.discovery, "start")
check("and written", fileDoc().points["phun.spawn.custom.1234_5678_0"].discovery, "start")
wipe()
boot(shipped)
local newbie = stubs.player("newbie", 0)
check("a new character in the next world knows it", Unlocks.has(newbie, "phun.spawn.custom.1234_5678_0"), true)

-- ---------------------------------------------------------------------------
-- A point in the file replaces a shipped one of the same id: fixing a
-- placeholder's square without code.
-- ---------------------------------------------------------------------------
Core.saved.points["phun.spawn.test.home"] = {label = "Home", x = 11, y = 22, z = 0, discovery = "start"}
Store.save()
wipe()
boot(shipped)
check("the file's square wins over the shipped one", Core.points["phun.spawn.test.home"].x, 11)

-- ---------------------------------------------------------------------------
-- Remove.
-- ---------------------------------------------------------------------------
Store.rename("phun.spawn.custom.1234_5678_0", "Renamed")
check("remove takes it out", Store.removePoint("phun.spawn.custom.1234_5678_0"), true)
check("of the registry", Core.points["phun.spawn.custom.1234_5678_0"], nil)
check("and the file", fileDoc().points["phun.spawn.custom.1234_5678_0"], nil)
check("with its rename", fileDoc().labels["phun.spawn.custom.1234_5678_0"], nil)
point, why = Store.removePoint("phun.spawn.custom.1234_5678_0")
check("removing twice is refused", why, "IGUI_PhunTaxi_NotSavedPoint")

-- ---------------------------------------------------------------------------
-- A file that will not write: the change is undone and says so.
-- ---------------------------------------------------------------------------
local realWriter = getFileWriter
getFileWriter = function()
    return nil
end
point, why = Store.addPoint(50, 60, 0, "Nowhere")
check("an unwritable file refuses the add", why, "IGUI_PhunTaxi_NotSaved")
check("and it is not registered", Core.points["phun.spawn.custom.50_60_0"], nil)
check("or left in memory to be written later", Core.saved.points["phun.spawn.custom.50_60_0"], nil)
local before = Core.points["phun.spawn.test.home"].label
point, why = Store.rename("phun.spawn.test.home", "Something")
check("an unwritable file refuses a rename", why, "IGUI_PhunTaxi_NotSaved")
check("and the name is put back", Core.points["phun.spawn.test.home"].label, before)
getFileWriter = realWriter

-- ---------------------------------------------------------------------------
-- A hand edit with problems: the good lines count, the bad ones are named.
-- ---------------------------------------------------------------------------
stubs.files[FILE] = [[{
  "points": {
    "ok.one": {"label": "Fine", "x": 1, "y": 2},
    "bad.kind": {"label": "Typo", "x": 1, "y": 2, "discovery": "strat"},
    "ok.phone": {"label": "Diner", "x": 5, "y": 6, "discovery": "start", "phone": "S"},
    "bad.phone": {"label": "Wall", "x": 5, "y": 6, "phone": "up"},
    "bad.label": {"x": 1, "y": 2},
    "bad.xy": {"label": "No square"}
  },
  "phones": {
    "whatever": {"x": 100, "y": 200, "facing": "E", "sprite": "phuninteriors_01_18"},
    "bad.facing": {"x": 1, "y": 1, "facing": "up"}
  },
  "labels": {"ok.one": "Better", "bad.empty": ""}
}]]
wipe()
local problems = Store.load()
check("each bad entry is reported", #problems, 6)
check("a good point is read", Core.saved.points["ok.one"] ~= nil, true)
check("defaulting to explore", Core.saved.points["ok.one"].discovery, "explore")
check("a mistyped kind is left out, not guessed", Core.saved.points["bad.kind"], nil)
check("a point can ask for a phone", Core.saved.points["ok.phone"] and Core.saved.points["ok.phone"].phone, "S")
check("a bad phone facing is left out", Core.saved.points["bad.phone"], nil)
check("a phone is keyed by its own square", Core.saved.phones["100_200_0"] ~= nil, true)
check("not what the file called it", Core.saved.phones["whatever"], nil)
check("an old file's sprite is dropped", Core.saved.phones["100_200_0"] and Core.saved.phones["100_200_0"].sprite, nil)
check("a bad facing is left out", Core.saved.phones["bad.facing"], nil)
check("an empty rename is left out", Core.saved.labels["bad.empty"], nil)

-- ---------------------------------------------------------------------------
-- A file that does not parse is not written over.
-- ---------------------------------------------------------------------------
local broken = '{"points": {"a": {"label": "A", "x": 1, "y": 2},}}'
stubs.files[FILE] = broken
wipe()
boot(shipped)
check("a broken file still boots", Core.points["phun.spawn.test.home"] ~= nil, true)
check("and is marked unreadable", Store.unreadable, true)
point, why = Store.addPoint(70, 80, 0, "Later")
check("changes are refused until it reads", why, "IGUI_PhunTaxi_NotSaved")
check("and the file is untouched", stubs.files[FILE], broken)

-- ---------------------------------------------------------------------------
-- Kept phones.
-- ---------------------------------------------------------------------------
stubs.files = {}
wipe()
boot()
PhoneSwap.add(1000, 2000, 0, "W", "phuninteriors_01_18")
local key = "1000_2000_0"
check("keeping writes the phone", Store.keepPhone(key, PhoneSwap.store()[key]), true)
check("its square and facing", fileDoc().phones[key].facing, "W")

-- The wipe: no ModData record, only the file.
wipe()
boot()
local record = PhoneSwap.store()[key]
check("a kept phone gets a record in the new world", record ~= nil, true)
check("marked kept", record and record.kept, true)
local phonePoint = Core.points[Core.phonePointId(1000, 2000, 0)]
check("and its point is registered", phonePoint ~= nil, true)
check("under the id the client rings by", phonePoint and phonePoint.id, "phun.spawn.phone.1000_2000_0")
check("in front of the phone", phonePoint and (phonePoint.x .. "," .. phonePoint.y), "999,2000")
check("marked saved", phonePoint and phonePoint.saved, true)
check("it spaces the random swap", PhoneSwap.farEnough(1100, 2000), false)
check("and is never forgotten", PhoneSwap.forget(1000, 2000, 0), false)
check("so its point stays", Core.points["phun.spawn.phone.1000_2000_0"] ~= nil, true)

check("the key comes back out of the point id", PhoneSwap.keyOfPoint("phun.spawn.phone.1000_2000_0"), key)
check("and not out of anything else", PhoneSwap.keyOfPoint("phun.spawn.custom.1_2_0"), nil)

point = PhoneSwap.release(key)
check("release returns the point", point ~= nil, true)
check("no longer saved", point and point.saved, false)
check("out of the file", fileDoc().phones[key], nil)
check("an ordinary phone again, so forgettable", PhoneSwap.forget(1000, 2000, 0), true)
point, why = PhoneSwap.release(key)
check("releasing what is not kept is refused", why, "IGUI_PhunTaxi_NotKept")

-- A phone taken out of the file by hand goes back to ordinary on the next
-- adopt, and one added by hand is picked up.
wipe()
boot()
PhoneSwap.add(3000, 3000, 0, "N", "phuninteriors_01_19")
Store.keepPhone("3000_3000_0", PhoneSwap.store()["3000_3000_0"])
Core.saved.phones["3000_3000_0"] = nil
Core.saved.phones["4000_4000_0"] = {x = 4000, y = 4000, z = 0, facing = "S"}
PhoneSwap.adopt()
check("dropped from the file is not kept", PhoneSwap.store()["3000_3000_0"].kept, nil)
check("added to the file is", PhoneSwap.store()["4000_4000_0"].kept, true)

-- ---------------------------------------------------------------------------
-- The commands: admins only, and reload.
-- ---------------------------------------------------------------------------
stubs.files = {}
wipe()
boot(shipped)
local sent = {}
Core.respond = function(player, command, args)
    table.insert(sent, {command = command, args = args})
end
local function lastSent(command)
    for i = #sent, 1, -1 do
        if sent[i].command == command then
            return sent[i].args
        end
    end
    return nil
end

Core.isLocal = false
local nobody = stubs.player("nobody", 400)
local boss = stubs.player("boss", 0)
boss.getAccessLevel = function()
    return "admin"
end

Commands[Core.commands.adminAddPoint](nobody, {x = 5, y = 6, z = 0, label = "Mine"})
check("a player cannot add a point", Core.points["phun.spawn.custom.5_6_0"], nil)
check("or write the file", stubs.files[FILE], nil)

Commands[Core.commands.adminAddPoint](boss, {x = 5, y = 6, z = 0, label = "Ours"})
check("an admin can", Core.points["phun.spawn.custom.5_6_0"] ~= nil, true)
check("and is told", lastSent(Core.commands.notify).text, "IGUI_PhunTaxi_PointAdded")
check("with a fresh editor list", lastSent(Core.commands.adminPoints) ~= nil, true)

local listed
for _, row in ipairs(lastSent(Core.commands.adminPoints).points) do
    if row.id == "phun.spawn.custom.5_6_0" then
        listed = row
    end
end
check("the editor sees it as saved", listed and listed.saved, true)

Commands[Core.commands.adminSetKind](boss, {id = "phun.spawn.custom.5_6_0", discovery = "granted"})
check("an admin can change its kind", Core.points["phun.spawn.custom.5_6_0"].discovery, "granted")

-- A hand edit made while the server runs, read in by reload.
local doc = fileDoc()
doc.points["hand.edit"] = {label = "By hand", x = 7, y = 8}
doc.points["phun.spawn.custom.5_6_0"] = nil
stubs.files[FILE] = json.encodePretty(doc)
Commands[Core.commands.admin](boss, {action = "reload"})
check("reload registers a point added by hand", Core.points["hand.edit"] ~= nil, true)
check("and drops one taken out", Core.points["phun.spawn.custom.5_6_0"], nil)
check("and the shipped points stay", Core.points["phun.spawn.test.home"] ~= nil, true)

-- A reload of a broken edit keeps what was running and will not write.
stubs.files[FILE] = broken
Commands[Core.commands.admin](boss, {action = "reload"})
check("a broken reload keeps what was read last", Core.points["hand.edit"] ~= nil, true)
Commands[Core.commands.adminAddPoint](boss, {x = 9, y = 9, z = 0, label = "Blocked"})
check("and refuses to write over the edit", stubs.files[FILE], broken)
check("saying so", lastSent(Core.commands.notify).text, "IGUI_PhunTaxi_NotSaved")

-- ---------------------------------------------------------------------------
-- Deleting: a shipped point is tombstoned, and stays gone through a reboot
-- and a wipe, because the code registers it again every boot.
-- ---------------------------------------------------------------------------
local function shippedTwo()
    shipped()
    Core.registerPoint("phun.spawn.test.away", {label = "Away", x = 30, y = 40, discovery = Core.discovery.start})
    Core.registerPoint("phun.spawn.test.far", {label = "Far", x = 50, y = 60})
end

stubs.files = {}
wipe()
boot(shippedTwo)
sent = {}
local player = stubs.player("walker", 1)
Unlocks.grant(player, "phun.spawn.test.far")
check("a player found the far point", Unlocks.has(player, "phun.spawn.test.far"), true)

Commands[Core.commands.adminRemovePoint](nobody, {id = "phun.spawn.test.far"})
check("a player cannot delete a point", Core.points["phun.spawn.test.far"] ~= nil, true)

Commands[Core.commands.adminRemovePoint](boss, {id = "phun.spawn.test.far"})
check("an admin can delete a shipped point", Core.points["phun.spawn.test.far"], nil)
check("and is told", lastSent(Core.commands.notify).text, "IGUI_PhunTaxi_PointDeleted")
check("the tombstone is in the file", fileDoc().deleted["phun.spawn.test.far"], true)
check("the player no longer has it", Unlocks.has(player, "phun.spawn.test.far"), false)
listed = nil
for _, row in ipairs(lastSent(Core.commands.adminPoints).points) do
    if row.id == "phun.spawn.test.far" then
        listed = row
    end
end
check("the editor still lists it, as deleted", listed and listed.deleted, true)
point, why = Store.deletePoint("phun.spawn.test.far")
check("deleting twice is refused", why, "IGUI_PhunTaxi_AlreadyDeleted")
Store.restorePoint("phun.spawn.test.far")
check("an unlock survives delete and restore", Unlocks.has(player, "phun.spawn.test.far"), true)
Store.deletePoint("phun.spawn.test.far")

-- A reboot and a wipe: the code registers it again, and the tombstone holds.
wipe()
boot(shippedTwo)
check("a wipe keeps it deleted", Core.points["phun.spawn.test.far"], nil)
check("in the graveyard", Core.deleted["phun.spawn.test.far"] ~= nil, true)
check("and the rest are there", Core.points["phun.spawn.test.away"] ~= nil, true)

-- Only the last start point is refused.
Commands[Core.commands.adminRemovePoint](boss, {id = "phun.spawn.test.away"})
check("a start point can go while another is left", Core.points["phun.spawn.test.away"], nil)
Commands[Core.commands.adminRemovePoint](boss, {id = "phun.spawn.test.home"})
check("the last start point cannot", Core.points["phun.spawn.test.home"] ~= nil, true)
check("saying so", lastSent(Core.commands.notify).text, "IGUI_PhunTaxi_LastStart")

-- A phone is released or taken down, not deleted.
Core.registerPoint("phun.spawn.phone.1_2_0", {label = "Phone", x = 2, y = 2, discovery = Core.discovery.used})
point, why = Store.deletePoint("phun.spawn.phone.1_2_0")
check("a phone cannot be deleted", why, "IGUI_PhunTaxi_CannotDeletePhone")

-- Restore brings it back, with the rename it had.
Store.rename("phun.spawn.test.away", "Over there")
Commands[Core.commands.adminRestorePoint](boss, {id = "phun.spawn.test.away"})
check("an admin can restore a point", Core.points["phun.spawn.test.away"] ~= nil, true)
check("with its rename", Core.points["phun.spawn.test.away"].label, "Over there")
check("and the tombstone leaves the file", fileDoc().deleted["phun.spawn.test.away"], nil)
Commands[Core.commands.adminRestorePoint](boss, {id = "phun.spawn.test.away"})
check("restoring twice is refused", lastSent(Core.commands.notify).text, "IGUI_PhunTaxi_NotDeleted")

-- A point added on a square is removed from the file, not tombstoned, so
-- the next point added there is not caught by it.
Commands[Core.commands.adminAddPoint](boss, {x = 70, y = 80, z = 0, label = "Here"})
Commands[Core.commands.adminRemovePoint](boss, {id = "phun.spawn.custom.70_80_0"})
check("an added point is removed", Core.points["phun.spawn.custom.70_80_0"], nil)
check("from the file", fileDoc().points["phun.spawn.custom.70_80_0"], nil)
check("with no tombstone", fileDoc().deleted["phun.spawn.custom.70_80_0"], nil)
check("saying removed", lastSent(Core.commands.notify).text, "IGUI_PhunTaxi_PointRemoved")

-- A file entry standing in for a shipped point is tombstoned, and kept.
doc = fileDoc()
doc.points["phun.spawn.test.far"] = {label = "Far, fixed", x = 51, y = 61}
stubs.files[FILE] = json.encodePretty(doc)
Commands[Core.commands.admin](boss, {action = "reload"})
Commands[Core.commands.adminRemovePoint](boss, {id = "phun.spawn.test.far"})
check("a file entry over a shipped point is deleted", Core.points["phun.spawn.test.far"], nil)
check("and kept in the file", fileDoc().points["phun.spawn.test.far"] ~= nil, true)
Commands[Core.commands.adminRestorePoint](boss, {id = "phun.spawn.test.far"})
check("so restore brings the fixed one back", Core.points["phun.spawn.test.far"].x, 51)

-- A reload of a hand edit that takes a tombstone out, or puts one in.
doc = fileDoc()
doc.deleted = {["phun.spawn.test.away"] = true}
stubs.files[FILE] = json.encodePretty(doc)
Commands[Core.commands.admin](boss, {action = "reload"})
check("reload applies a tombstone added by hand", Core.points["phun.spawn.test.away"], nil)
doc.deleted = {}
stubs.files[FILE] = json.encodePretty(doc)
Commands[Core.commands.admin](boss, {action = "reload"})
check("and lifts one taken out", Core.points["phun.spawn.test.away"] ~= nil, true)

-- A file that will not write puts the point back.
getFileWriter = function()
    return nil
end
point, why = Store.deletePoint("phun.spawn.test.away")
check("an unwritable file refuses a delete", why, "IGUI_PhunTaxi_NotSaved")
check("and the point is put back", Core.points["phun.spawn.test.away"] ~= nil, true)
check("with no tombstone left in memory", Core.saved.deleted["phun.spawn.test.away"], nil)
getFileWriter = realWriter

-- ---------------------------------------------------------------------------
-- The written file is one a person can read and diff.
-- ---------------------------------------------------------------------------
stubs.files = {}
wipe()
Store.save()
check("an empty store writes objects, not arrays", stubs.files[FILE]:find("%[") == nil, true)
check("and reads back", fileDoc() ~= nil, true)

Core.isLocal = true
os.exit(report.finish("store") > 0 and 1 or 0)
