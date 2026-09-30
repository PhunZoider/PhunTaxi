-- The spawn point registry and the unlock bookkeeping.
--
-- These are the two things that fail SILENTLY in game. A point that does not
-- register is a place nobody can go and nothing says so, and an unlock that
-- does not persist reads as the player misremembering. Neither shows up as an
-- error anywhere, which is why they are worth a spec while a UI is not.
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
local report = stubs.reporter()
local check = report.check

local function reset()
    Core.points = {}
    Core.regions = {}
    Core.unlocked = {}
    Core.data = {}
    Core.saved = {points = {}, phones = {}, labels = {}, deleted = {}, released = {}}
    Core.indexesBuilt = false
end

-- ---------------------------------------------------------------------------
-- Registration refuses what it cannot use, and says so rather than storing a
-- half point. A point with no label or no coordinates is one nobody can pick
-- or be put at, so accepting it would only move the failure further away.
-- ---------------------------------------------------------------------------
reset()
check("a good point registers", Core.registerPoint("a.point", {
    label = "A Point", x = 100, y = 200, z = 0
}) ~= nil, true)
check("no label is refused", Core.registerPoint("b.point", {x = 1, y = 2}), nil)
check("no coordinates are refused", Core.registerPoint("c.point", {label = "C"}), nil)
check("no definition is refused", Core.registerPoint("d.point"), nil)
check("no id is refused", Core.registerPoint(nil, {label = "D", x = 1, y = 2}), nil)
check("only the good one is stored", Core.points["a.point"] ~= nil, true)
check("and nothing else is", Core.points["b.point"], nil)

-- `mods`: any one active is enough, none active registers nothing, and a
-- list that is not a list of ids is refused rather than read as "none".
stubs.mods = {othermap = true}
check("mods not a list is refused", Core.registerPoint("m.bad", {label = "M", x = 1, y = 2, mods = "othermap"}), nil)
check("nor a list with a non string", Core.registerPoint("m.bad", {label = "M", x = 1, y = 2, mods = {1}}), nil)
check("no mod active registers nothing", Core.registerPoint("m.none", {label = "M", x = 1, y = 2, mods = {"absent"}}), nil)
check("and is not stored", Core.points["m.none"], nil)
check("one of them active is enough", Core.registerPoint("m.one", {
    label = "M", x = 1, y = 2, mods = {"absent", "othermap"}
}) ~= nil, true)
check("an empty list asks for nothing", Core.registerPoint("m.empty", {label = "M", x = 1, y = 2, mods = {}}) ~= nil, true)
check("a skipped id leaves what is there", Core.registerPoint("m.one", {label = "M2", x = 1, y = 2, mods = {"absent"}}), nil)
check("as it was", Core.points["m.one"].label, "M")
stubs.mods = {}

-- z defaults to ground rather than to nil, because every reader compares it
-- and a nil would make a point on no level at all.
check("z defaults to 0", Core.points["a.point"].z, 0)
-- Discovery defaults to explore, never to start: the safe default is the one
-- that gives nothing away, so a point that is meant to be known has to say so.
check("discovery defaults to explore", Core.points["a.point"].discovery, "explore")

-- ---------------------------------------------------------------------------
-- The sort is stable. pairs() order is not, ties are routine, and without the
-- id tail one save would draw the same list in two different orders.
-- ---------------------------------------------------------------------------
reset()
Core.registerPoint("z.late", {label = "Same", x = 1, y = 1, priority = 1})
Core.registerPoint("a.early", {label = "Same", x = 1, y = 1, priority = 1})
Core.registerPoint("m.first", {label = "Aardvark", x = 1, y = 1, priority = 0})
local sorted = Core.sortedPoints()
check("priority wins", sorted[1].id, "m.first")
check("then label, then id", sorted[2].id, "a.early")
check("and the tie breaks deterministically", sorted[3].id, "z.late")

-- ---------------------------------------------------------------------------
-- The reverse index rebuilds lazily, on the first read after a registration.
-- That is what lets a third party register from any vanilla hook, including
-- one that fires long after our own boot sequence, and it is the reason
-- nothing may warn about a missing link at boot.
-- ---------------------------------------------------------------------------
reset()
Core.registerPoint("r.one", {label = "One", x = 1, y = 1, region = "Muldraugh"})
check("region has one", #Core.pointsInRegion("Muldraugh"), 1)
Core.registerPoint("r.two", {label = "Two", x = 2, y = 2, region = "Muldraugh"})
check("a point registered after a read is indexed", #Core.pointsInRegion("Muldraugh"), 2)
check("a point with no region is not in a named one", #Core.pointsInRegion("West Point"), 0)
Core.registerPoint("r.three", {label = "Three", x = 3, y = 3})
check("an unregioned point lands in the empty region", #Core.pointsInRegion(nil), 1)

-- Removing one re-indexes too, and does NOT walk anybody's unlock list.
check("removing reports it removed something", Core.removePoint("r.two"), true)
check("removing twice reports nothing", Core.removePoint("r.two"), false)
check("the index followed", #Core.pointsInRegion("Muldraugh"), 1)

-- ---------------------------------------------------------------------------
-- nearestPoint answers in SQUARED distance and only on the same level. The
-- squaring is what lets the caller compare against radius * radius without a
-- square root; the level test is what stops a point on a roof being found by
-- somebody standing under it.
-- ---------------------------------------------------------------------------
reset()
Core.registerPoint("n.close", {label = "Close", x = 10, y = 10, z = 0})
Core.registerPoint("n.far", {label = "Far", x = 100, y = 100, z = 0})
Core.registerPoint("n.upstairs", {label = "Upstairs", x = 11, y = 10, z = 1})
local near, distance = Core.nearestPoint(13, 14, 0)
check("the nearest on this level wins", near.id, "n.close")
check("and the distance is squared", distance, 25)
local above = Core.nearestPoint(11, 10, 1)
check("a level of its own is answered separately", above.id, "n.upstairs")

-- ---------------------------------------------------------------------------
-- Unlocks.
--
-- The starters are granted on READ rather than stamped once at character
-- creation, so a point added to the start set in a later version reaches
-- existing characters with no migration to write.
-- ---------------------------------------------------------------------------
reset()
Core.settings.DiscoveryRadius = 10
Core.registerPoint("u.start", {label = "Start", x = 0, y = 0, discovery = Core.discovery.start})
Core.registerPoint("u.explore", {label = "Explore", x = 500, y = 500, discovery = Core.discovery.explore})

local bob = stubs.player("bob")
check("a starter is known without being granted", Unlocks.has(bob, "u.start"), true)
check("and an explorable one is not", Unlocks.has(bob, "u.explore"), false)

-- Granting reports whether it CHANGED anything, so a caller can use the
-- return value to decide whether to tell the player. Telling somebody twice
-- that they found the same place is how a notification becomes noise.
check("granting changes something", Unlocks.grant(bob, "u.explore"), true)
check("granting again changes nothing", Unlocks.grant(bob, "u.explore"), false)
check("granting a point that does not exist changes nothing", Unlocks.grant(bob, "u.nope"), false)
check("and it is known now", Unlocks.has(bob, "u.explore"), true)

-- The truth is the account record, not the cache. Dropping the cache must
-- not drop the unlock, because that is exactly what a reconnect does.
Core.unlocked = {}
check("an unlock survives the cache being dropped", Unlocks.has(bob, "u.explore"), true)

-- And it survives the CHARACTER. Dying makes a new character with fresh
-- modData, and an unlock is only worth anything to that new character: it is
-- the one choosing where to wake up.
local bob2 = stubs.player("bob")
check("a new character starts with fresh modData", bob2:getModData() ~= bob:getModData(), true)
check("and still knows what the player found", Unlocks.has(bob2, "u.explore"), true)
check("somebody else does not", Unlocks.has(stubs.player("nobody"), "u.explore"), false)

-- A character from before unlocks were per player carries its list in its
-- modData. It is folded into the account once, and cleared, so there is one
-- list rather than two that can disagree.
local old = stubs.player("oldtimer")
old:getModData()[Core.consts.unlockedKey] = {["u.explore"] = true}
old:getModData()[Core.consts.lastChoiceKey] = "u.start"
check("a legacy unlock is honoured", Unlocks.has(old, "u.explore"), true)
check("and taken off the character", old:getModData()[Core.consts.unlockedKey], nil)
check("the legacy last choice comes too", Unlocks.lastChoice(old), "u.start")
check("and is taken off as well", old:getModData()[Core.consts.lastChoiceKey], nil)
check("the next character inherits it", Unlocks.has(stubs.player("oldtimer"), "u.explore"), true)

-- And a point that has been removed from the registry is filtered on read
-- rather than deleted, so putting the set back costs nobody their exploring.
Core.removePoint("u.explore")
check("a removed point is not reported as known", Unlocks.has(bob, "u.explore"), false)
Core.registerPoint("u.explore", {label = "Explore", x = 500, y = 500})
check("and comes back when the point does", Unlocks.has(bob, "u.explore"), true)

-- ---------------------------------------------------------------------------
-- Discovery is a distance test against the option, and it only ever unlocks
-- an `explore` point. A `built` or `granted` point is unlocked by the thing
-- that made it, and walking past one must not shortcut that.
-- ---------------------------------------------------------------------------
reset()
Core.settings.DiscoveryRadius = 10
Core.registerPoint("d.explore", {label = "Explore", x = 100, y = 100, discovery = Core.discovery.explore})
Core.registerPoint("d.granted", {label = "Granted", x = 300, y = 300, discovery = Core.discovery.granted})

local sue = stubs.player("sue")
sue.moveTo(200, 200, 0)
check("too far finds nothing", Unlocks.checkDiscovery(sue), nil)

sue.moveTo(106, 108, 0)
-- 6 and 8 out is exactly 10 away, which is the radius: inside, because the
-- test is <= and a boundary that refuses at exactly the stated range reads as
-- the range being one short.
local found = Unlocks.checkDiscovery(sue)
check("at exactly the radius it is found", found and found.id, "d.explore")
check("and finding it again changes nothing", Unlocks.checkDiscovery(sue), nil)

sue.moveTo(300, 300, 0)
check("standing on a granted point does not unlock it", Unlocks.checkDiscovery(sue), nil)

-- ---------------------------------------------------------------------------
-- The payload honours ShowUndiscovered on THIS side. A client handed the
-- coordinates can draw them whatever the option says, so an option enforced
-- only in the UI is not enforced at all.
-- ---------------------------------------------------------------------------
reset()
Core.registerPoint("p.known", {label = "Known", x = 1, y = 1, discovery = Core.discovery.start})
Core.registerPoint("p.unknown", {label = "Unknown", x = 900, y = 900})

local amy = stubs.player("amy")
Core.settings.ShowUndiscovered = false
local payload = Core.tools.isEmpty(Unlocks.payloadFor(amy)) and {} or Unlocks.payloadFor(amy)
check("hidden means only what is known is sent", #payload, 1)
check("and it is the known one", payload[1].id, "p.known")

Core.settings.ShowUndiscovered = true
payload = Unlocks.payloadFor(amy)
check("shown means both are sent", #payload, 2)
local unknown
for _, entry in ipairs(payload) do
    if entry.id == "p.unknown" then
        unknown = entry
    end
end
check("the unknown one is flagged", unknown.known, false)
check("and carries no coordinates", unknown.x, nil)

-- ---------------------------------------------------------------------------
-- A discovery is sent as one entry and merged on the client. The merged list
-- has to be the list a full payload would have sent, or the picker shows a
-- different order (or a stale undiscovered row) until it next refreshes.
-- ---------------------------------------------------------------------------
local function ids(list)
    local out = {}
    for _, e in ipairs(list) do
        table.insert(out, e.id .. (e.known and "+" or "-") .. tostring(e.x))
    end
    return table.concat(out, " ")
end
for _, show in ipairs({false, true}) do
    reset()
    Core.settings.ShowUndiscovered = show
    Core.registerPoint("m.first", {label = "Zed", x = 1, y = 1, discovery = Core.discovery.start, priority = 0})
    Core.registerPoint("m.late", {label = "Alpha", x = 2, y = 2, priority = 10})
    Core.registerPoint("m.mid", {label = "Mid", x = 3, y = 3, priority = 0})
    Core.registerPoint("m.same", {label = "Mid", x = 4, y = 4, priority = 0})
    local mo = stubs.player("mo" .. tostring(show))
    for _, id in ipairs({"m.late", "m.same", "m.mid"}) do
        local before = Unlocks.payloadFor(mo)
        Unlocks.grant(mo, id)
        Core.mergePoint(before, Unlocks.entryFor(Core.points[id], true))
        check("merging " .. id .. (show and " over an undiscovered row" or " into the list") ..
                  " matches a full payload", ids(before), ids(Unlocks.payloadFor(mo)))
    end
end
Core.settings.ShowUndiscovered = false

os.exit(report.finish("points") > 0 and 1 or 0)
