require "PhunTaxi/core"
require "PhunTaxi/points"
require "PhunTaxi/phones"
local Core = PhunTaxi

-- ---------------------------------------------------------------------------
-- The shipped spawn points.
--
-- Registered on our own OnRegisterPoints event, which is what a generated
-- file reads best on. A third party should hook Events.OnInitGlobalModData
-- instead: both routes work, but theirs cannot be broken by load order. See
-- README.md and interiors.lua for why.
--
-- Each one has been checked in game: the square is open floor, and the square
-- behind it, the way `phone` says, takes a pay phone. That phone is what
-- makes a start point somewhere a taxi can be called from and ridden to. A
-- point moved here needs both checked again, because nothing in code can
-- tell a wall from a floor.
--
-- Sourced deliberately rather than by arithmetic: a set of points laid out on
-- a grid would be three lines shorter and would put half of them in the
-- river.
-- ---------------------------------------------------------------------------

Events[Core.events.OnRegisterPoints].Add(function()

    Core.registerPoint("phun.spawn.muldraugh.smokeys", {
        label = "Muldraugh - Smokeys",
        region = "Muldraugh",
        x = 10629,
        y = 9230,
        z = 0,
        -- Known from character creation: somewhere has to be, or a new
        -- character has nowhere at all to wake up.
        discovery = Core.discovery.start,
        priority = 0,
        -- The phone behind the arrival square, so the taxi can be called here.
        phone = "E"
    })

    Core.registerPoint("phun.spawn.rosewood.motel", {
        label = "Rosewood - Motel",
        region = "Rosewood",
        x = 8190,
        y = 11505,
        z = 0,
        -- Known from character creation: somewhere has to be, or a new
        -- character has nowhere at all to wake up.
        discovery = Core.discovery.start,
        priority = 0,
        -- The phone behind the arrival square, so the taxi can be called here.
        phone = "S"
    })

    Core.registerPoint("phun.spawn.riverside.courthouse", {
        label = "Riverside - Courthouse",
        region = "Riverside",
        x = 6491,
        y = 5459,
        z = 0,
        -- Known from character creation: somewhere has to be, or a new
        -- character has nowhere at all to wake up.
        discovery = Core.discovery.start,
        priority = 0,
        -- The phone behind the arrival square, so the taxi can be called here.
        phone = "S"
    })

    Core.registerPoint("phun.spawn.westpoint.picnic", {
        label = "West Point - Picnic Area",
        region = "West Point",
        x = 11622,
        y = 6634,
        z = 0,
        -- Known from character creation: somewhere has to be, or a new
        -- character has nowhere at all to wake up.
        discovery = Core.discovery.start,
        priority = 0,
        -- The phone behind the arrival square, so the taxi can be called here.
        phone = "E"
    })

end)

-- ---------------------------------------------------------------------------
-- The shipped pay phone spots.
--
-- Candidates, not kept phones: each world draws them once in a random order,
-- and a spot goes up only if it is PhoneDistance (or its zone's) from every
-- phone already drawn or standing, so a town gets one of its spots, a
-- different one each world. See candidates.lua and PhoneSwap.drawCandidates.
-- They were kept phones once, and every world got every one of them.
--
-- Each line is in the store file's shape, so one can be copied out of a
-- PhunTaxi.json as it is: `x, y, z` is where the traveller STANDS, and
-- `facing` puts the phone on the square behind, which is the square the
-- candidate is offered on. `label` names the phone if it wins, through a
-- shipped name only entry, so Reset name goes back to it. `mods = {...}`
-- offers the spot only when at least one of those mods is active.
--
-- A phone every world must have is a point's `phone` (above), or a kept
-- phone in Core.shipped, as Docs/modding.md describes.
-- ---------------------------------------------------------------------------

local spots = {{
    x = 10036,
    y = 12754,
    z = 0,
    facing = "S",
    label = "Community Center"
}, {
    x = 10081,
    y = 12806,
    z = 0,
    facing = "E",
    label = "Bakery"
}, {
    x = 10111,
    y = 12731,
    z = 0,
    facing = "S",
    label = "Ally"
}, {
    x = 10169,
    y = 12746,
    z = 0,
    facing = "S",
    label = "Videos"
}, {
    x = 10326,
    y = 9398,
    z = 0,
    facing = "E",
    label = "Logging"
}, {
    x = 10341,
    y = 9324,
    z = 0,
    facing = "E",
    label = "Logging"
}, {
    x = 10346,
    y = 12785,
    z = 0,
    facing = "E",
    label = "Church"
}, {
    x = 10359,
    y = 12625,
    z = 0,
    facing = "E",
    label = "Residential"
}, {
    x = 10606,
    y = 10461,
    z = 0,
    facing = "S",
    label = "Video Store"
}, {
    x = 10611,
    y = 10332,
    z = 0,
    facing = "S",
    label = "Barbers"
}, {
    x = 10613,
    y = 10110,
    z = 0,
    facing = "E",
    label = "Pizza Whirled"
}, {
    x = 10614,
    y = 9466,
    z = 0,
    facing = "E",
    label = "Laundromat"
}, {
    x = 10620,
    y = 9637,
    z = 0,
    facing = "E",
    label = "Spiffos"
}, {
    x = 10620,
    y = 9367,
    z = 0,
    facing = "S",
    label = "Storage"
}, {
    x = 10623,
    y = 9609,
    z = 0,
    facing = "E",
    label = "Short Circuit"
}, {
    x = 10623,
    y = 10857,
    z = 0,
    facing = "S",
    label = "Motel",
    mods = {"Muldraugh-Checkpoint"}
}, {
    x = 10624,
    y = 10565,
    z = 0,
    facing = "S",
    label = "Diner"
}, {
    x = 10627,
    y = 10520,
    z = 0,
    facing = "E",
    label = "Diner"
}, {
    x = 10626,
    y = 9689,
    z = 0,
    facing = "W",
    label = "Bank"
}, {
    x = 10628,
    y = 9963,
    z = 0,
    facing = "E",
    label = "School"
}, {
    x = 10628,
    y = 9762,
    z = 0,
    facing = "W",
    label = "Gas Station"
}, {
    x = 10645,
    y = 11061,
    z = 0,
    facing = "W",
    label = "Machine Shop",
    mods = {"Muldraugh-Checkpoint"}
}, {
    x = 10689,
    y = 10322,
    z = 0,
    facing = "S",
    label = "Office"
}, {
    x = 10702,
    y = 10109,
    z = 0,
    facing = "E",
    label = "Storage"
}, {
    x = 10778,
    y = 10183,
    z = 0,
    facing = "N",
    label = "Church"
}, {
    x = 11088,
    y = 9235,
    z = 0,
    facing = "W",
    label = "Train Station"
}, {
    x = 11340,
    y = 6766,
    z = 0,
    facing = "N",
    label = "School"
}, {
    x = 11352,
    y = 6728,
    z = 0,
    facing = "S",
    label = "Food Market"
}, {
    x = 11514,
    y = 8838,
    z = 0,
    facing = "N",
    label = "General Store"
}, {
    x = 11669,
    y = 7063,
    z = 0,
    facing = "E",
    label = "Zipee Market"
}, {
    x = 11677,
    y = 8193,
    z = 0,
    facing = "S",
    label = "Police Station",
    mods = {"Crossroads-Checkpoint"}
}, {
    x = 11682,
    y = 8363,
    z = 0,
    facing = "W",
    label = "Office",
    mods = {"Crossroads-Checkpoint"}
}, {
    x = 11858,
    y = 6889,
    z = 0,
    facing = "S",
    label = "Hair Genesis"
}, {
    x = 11903,
    y = 6827,
    z = 0,
    facing = "S",
    label = "Moores"
}, {
    x = 11915,
    y = 6916,
    z = 0,
    facing = "E",
    label = "Bank"
}, {
    x = 11941,
    y = 6787,
    z = 0,
    facing = "E",
    label = "Laundromat"
}, {
    x = 11956,
    y = 6889,
    z = 0,
    facing = "E",
    label = "Town Hall"
}, {
    x = 11979,
    y = 6988,
    z = 0,
    facing = "E",
    label = "Church"
}, {
    x = 11985,
    y = 6956,
    z = 0,
    facing = "S",
    label = "High Wire"
}, {
    x = 11986,
    y = 6815,
    z = 0,
    facing = "S",
    label = "Spiffos"
}, {
    x = 12062,
    y = 6806,
    z = 0,
    facing = "S",
    label = "Twiggys"
}, {
    x = 12102,
    y = 6790,
    z = 0,
    facing = "E",
    label = "Stendo's"
}, {
    x = 12130,
    y = 7031,
    z = 0,
    facing = "W",
    label = "Storage"
}, {
    x = 12131,
    y = 7101,
    z = 0,
    facing = "W",
    label = "Trade Winds"
}, {
    x = 1768,
    y = 14793,
    z = 0,
    facing = "S",
    label = "Gear & Supply"
}, {
    x = 1869,
    y = 14782,
    z = 0,
    facing = "E",
    label = "Ice Cream"
}, {
    x = 1887,
    y = 14476,
    z = 0,
    facing = "E",
    label = "Public Pool"
}, {
    x = 2254,
    y = 14308,
    z = 0,
    facing = "E",
    label = "School"
}, {
    x = 2264,
    y = 14368,
    z = 0,
    facing = "E",
    label = "School"
}, {
    x = 2472,
    y = 14478,
    z = 0,
    facing = "S",
    label = "Greenes"
}, {
    x = 2483,
    y = 14024,
    z = 0,
    facing = "E",
    label = "Mechanics"
}, {
    x = 2510,
    y = 14061,
    z = 0,
    facing = "W",
    label = "Vacant"
}, {
    x = 2581,
    y = 14477,
    z = 0,
    facing = "E",
    label = "Tobacco Shop"
}, {
    x = 2867,
    y = 14428,
    z = 0,
    facing = "S",
    label = "A-1 Warehouse"
}, {
    x = 2927,
    y = 14475,
    z = 0,
    facing = "E",
    label = "A-1 Hay"
}, {
    x = 3833,
    y = 14431,
    z = 0,
    facing = "S",
    label = "Brotts"
}, {
    x = 5833,
    y = 5386,
    z = 0,
    facing = "S",
    label = "Autoshop"
}, {
    x = 5860,
    y = 5371,
    z = 0,
    facing = "E",
    label = "Gas Station"
}, {
    x = 6294,
    y = 5292,
    z = 0,
    facing = "E",
    label = "Steakhouse"
}, {
    x = 6363,
    y = 5215,
    z = 0,
    facing = "S",
    label = "Riparian"
}, {
    x = 6405,
    y = 5272,
    z = 0,
    facing = "S",
    label = "Saucy"
}, {
    x = 6490,
    y = 5296,
    z = 0,
    facing = "S",
    label = "Cally's Gifts"
}, {
    x = 6523,
    y = 5239,
    z = 0,
    facing = "E",
    label = "FashionBelle"
}, {
    x = 6523,
    y = 5270,
    z = 0,
    facing = "E",
    label = "Lola Limon"
}, {
    x = 6540,
    y = 5190,
    z = 0,
    facing = "E",
    label = "Docks"
}, {
    x = 6554,
    y = 5235,
    z = 0,
    facing = "S",
    label = "Boat Club"
}, {
    x = 6578,
    y = 5299,
    z = 0,
    facing = "E",
    label = "Pet Supplies"
}, {
    x = 6661,
    y = 5238,
    z = 0,
    facing = "N",
    label = "Childrens Medical Center"
}, {
    x = 7144,
    y = 6080,
    z = 0,
    facing = "S",
    label = "Motel"
}, {
    x = 7228,
    y = 8536,
    z = 0,
    facing = "E",
    label = "Church"
}, {
    x = 7240,
    y = 8161,
    z = 0,
    facing = "N",
    label = "Camping Supply"
}, {
    x = 7254,
    y = 8526,
    z = 0,
    facing = "E",
    label = "The Horseshoe"
}, {
    x = 7256,
    y = 8335,
    z = 0,
    facing = "S",
    label = "Farming & Rural Supply"
}, {
    x = 7264,
    y = 8241,
    z = 0,
    facing = "E",
    label = "EP Tools"
}, {
    x = 7265,
    y = 8437,
    z = 0,
    facing = "E",
    label = "The Good Book"
}, {
    x = 7266,
    y = 8171,
    z = 0,
    facing = "E",
    label = "The Fermented Watermelon"
}, {
    x = 7267,
    y = 8391,
    z = 0,
    facing = "E",
    label = "Police Station"
}, {
    x = 7320,
    y = 8286,
    z = 0,
    facing = "W",
    label = "Diner"
}, {
    x = 7826,
    y = 11888,
    z = 0,
    facing = "E",
    label = "Prison"
}, {
    x = 8028,
    y = 11587,
    z = 0,
    facing = "N",
    label = "Warehouse"
}, {
    x = 8035,
    y = 11499,
    z = 0,
    facing = "S",
    label = "Laundromat"
}, {
    x = 8052,
    y = 11145,
    z = 0,
    facing = "E",
    label = "Little Gas Station"
}, {
    x = 8079,
    y = 11734,
    z = 0,
    facing = "E",
    label = "Police Station"
}, {
    x = 8081,
    y = 11455,
    z = 0,
    facing = "E",
    label = "Jenny's"
}, {
    x = 8083,
    y = 11641,
    z = 0,
    facing = "N",
    label = "Court"
}, {
    x = 8095,
    y = 11528,
    z = 0,
    facing = "S",
    label = "Medical"
}, {
    x = 8099,
    y = 11720,
    z = 0,
    facing = "E",
    label = "Police Station"
}, {
    x = 8123,
    y = 11683,
    z = 0,
    facing = "E",
    label = "Back Lot"
}, {
    x = 8140,
    y = 11433,
    z = 0,
    facing = "S",
    label = "Ally"
}, {
    x = 8164,
    y = 11333,
    z = 0,
    facing = "E",
    label = "Mechanics"
}, {
    x = 8183,
    y = 8593,
    z = 0,
    facing = "S",
    label = "Warehouse",
    mods = {"Maplewood"}
}, {
    x = 8234,
    y = 8611,
    z = 0,
    facing = "S",
    label = "Lucky Noodle",
    mods = {"Maplewood"}
}, {
    x = 8238,
    y = 11341,
    z = 0,
    facing = "S",
    label = "Community Center"
}, {
    x = 8257,
    y = 11250,
    z = 0,
    facing = "S",
    label = "Storage"
}, {
    x = 8300,
    y = 8554,
    z = 0,
    facing = "S",
    label = "Police Station",
    mods = {"Maplewood"}
}, {
    x = 8303,
    y = 8580,
    z = 0,
    facing = "S",
    label = "Gas Station",
    mods = {"Maplewood"}
}, {
    x = 8304,
    y = 12173,
    z = 0,
    facing = "S",
    label = "Diner"
}, {
    x = 8330,
    y = 11262,
    z = 0,
    facing = "S",
    label = "Derelict Building"
}, {
    x = 8330,
    y = 14589,
    z = 0,
    facing = "W",
    label = "Lodge"
}, {
    x = 8728,
    y = 14093,
    z = 0,
    facing = "S",
    label = "Dark Lake Gas Station"
}, {
    x = 9010,
    y = 12299,
    z = 0,
    facing = "S",
    label = "Fiddlers Trail Store"
}, {
    x = 9999,
    y = 12672,
    z = 0,
    facing = "E",
    label = "School"
}}

for _, entry in ipairs(spots) do
    local px, py = Core.phoneBehind(entry.x, entry.y, entry.facing)
    if Core.addPhoneCandidate(px, py, entry.z, entry.facing, nil, entry.mods) then
        table.insert(Core.shipped, {
            id = Core.phonePointId(px, py, entry.z),
            label = entry.label
        })
    end
end

return Core
