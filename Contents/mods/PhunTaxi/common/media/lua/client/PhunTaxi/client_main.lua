if isServer() then
    return
end
require "PhunTaxi/points"
require "PhunTaxi/taxi"
local Core = PhunTaxi

-- ---------------------------------------------------------------------------
-- Client state and the small things that touch the screen.
--
-- Everything the client holds here is a COPY for drawing. The server decides
-- what a character knows, and a client that disagrees is simply drawing a
-- stale list: nothing here is allowed to be the reason a point can be picked.
-- ---------------------------------------------------------------------------

local Client = {}
Core.client = Client

-- The last payload the server sent. Nil until playerSetup has answered, which
-- the UI reads as "not ready yet" rather than as "you know nothing".
Client.points = nil
Client.lastChoice = nil
-- Whether the server says this character is new and still choosing, and
-- whether the spawn button would be honoured. Both are hints for drawing; the
-- server asks again when the button is pressed.
Client.pending = false
Client.canSpawn = false
-- Whether an admin's right click carries Spawn point setup and Spawn points.
-- Off until they turn it on in the editor, and off again next session: it
-- is clutter on every right click, wanted only while setting a world up.
Client.setupMenu = false

-- Each player's own volume for our two sounds, in Options, Mods, as
-- PhunSprinters does it. 100 is as shipped and 0 mutes it for them only.
local options = PZAPI and PZAPI.ModOptions and PZAPI.ModOptions:create(Core.name, getText("IGUI_PhunTaxi_Options"))
if options then
    options:addSlider("RingVolume", getText("IGUI_PhunTaxi_Options_RingVolume"), 0, 200, 5, 100,
        getText("IGUI_PhunTaxi_Options_RingVolume_tooltip"))
    options:addSlider("DriveOffVolume", getText("IGUI_PhunTaxi_Options_DriveOffVolume"), 0, 200, 5, 100,
        getText("IGUI_PhunTaxi_Options_DriveOffVolume_tooltip"))
end

--- The player's multiplier for one of the sliders above, 1 being as shipped.
function Client.volume(id)
    local option = options and options:getOption(id)
    local value = option and option:getValue()
    return (tonumber(value) or 100) * .01
end

--- A fresh picture of what this character knows.
--
-- Stored in one place and announced, rather than handed to whoever asked. Any
-- number of panels read it, and a payload delivered only to the caller is how
-- two views of one list come to disagree.
function Client.receivePoints(arguments)
    Client.points = arguments and arguments.points or {}
    if arguments and arguments.last then
        Client.lastChoice = arguments.last
    end
    Client.pending = arguments and arguments.pending == true
    Client.canSpawn = arguments and arguments.canSpawn == true
    if arguments and Client.notePhoneKeys then
        Client.notePhoneKeys(arguments.phones)
    end
    if Client.hushKnown then
        Client.hushKnown()
    end

    -- A new character is pointed at the taxi rather than handed the picker:
    -- the ride is something they walk up to. See client_taxi.lua.
    if Client.pending and Client.watchTaxi then
        Client.watchTaxi()
    end

    triggerEvent(Core.events.OnPointsReceived, Client.points)
end

function Client.notify(arguments)
    if not arguments or not arguments.text then
        return
    end
    local text = getText(arguments.text, arguments.arg)
    local player = getPlayer()
    if player then
        player:setHaloNote(text, 255, 255, 255, 300)
        -- On the player's own emitter, which moves with them, so it is heard
        -- where they land whether or not the move has reached this client yet.
        -- The drive off is the only sound a message carries, so it takes
        -- that slider.
        local volume = arguments.sound and Client.volume("DriveOffVolume") or 0
        if volume > 0 then
            local sound = player:playSound(arguments.sound)
            player:getEmitter():setVolume(sound, volume)
        end
    else
        Core.logLn(text)
    end
end

-- How long the single ring is that says a phone was found by walking near
-- it. Long enough to be one ring and not a click.
local FOUND_RING_MS = 2500

--- "You just found one." A phone brings its own line, and a phone found by
--- walking near it (it carries its square) rings once, since nothing was
--- picked up to say it counted.
function Client.announceUnlock(arguments)
    if not arguments then
        return
    end
    Client.notify({
        text = arguments.text or "IGUI_PhunTaxi_Discovered",
        arg = arguments.label
    })
    -- The one entry that changed, merged rather than the whole list sent
    -- again. Before the first payload there is nothing to merge into, and
    -- that payload will carry it.
    if arguments.point and Client.points then
        Core.mergePoint(Client.points, arguments.point)
        triggerEvent(Core.events.OnPointsReceived, Client.points)
        if Client.hushKnown then
            Client.hushKnown()
        end
    end
    local phone = arguments.phone
    if phone and Client.ringPhone then
        Client.ringPhone(phone.x, phone.y, phone.z, FOUND_RING_MS)
    end
end

--- Use the pay phone at `phone`'s square. Sends the square and nothing else;
--- the server decides whether it is a spawn point and whether we are close
--- enough to be using it.
function Client.usePhone(phone)
    if not phone then
        return
    end
    Core.dispatch(Core.commands.usePhone, {
        x = phone:getX(),
        y = phone:getY(),
        z = phone:getZ()
    })
end

function Client.choose(id)
    Core.dispatch(Core.commands.choose, {
        id = id
    })
end

--- Ask to be put at a point now. The server decides; see placement.lua.
function Client.spawn(id)
    Core.dispatch(Core.commands.spawn, {
        id = id
    })
end

--- A taxi from the phone at `from` ({x, y, z}) to point `id`, for a fare.
--- The server checks everything and charges; see server/rides.lua.
function Client.taxi(from, id)
    Core.dispatch(Core.commands.taxi, {
        x = from.x,
        y = from.y,
        z = from.z,
        id = id
    })
end

--- Build a phone from `kit` on `square`, facing `facing`.
function Client.buildPhone(square, facing, kit)
    Core.dispatch(Core.commands.buildPoint, {
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        facing = facing,
        item = kit:getID()
    })
end

function Client.takeDownPhone(phone)
    Core.dispatch(Core.commands.takeDownPhone, {
        x = phone:getX(),
        y = phone:getY(),
        z = phone:getZ()
    })
end

--- Ask for a fresh payload. Answered through receivePoints like any other.
function Client.refreshPoints()
    Core.dispatch(Core.commands.playerSetup, {})
end

-- ---------------------------------------------------------------------------
-- The admin editor. Everything is checked again on the server; these only
-- send the request.
-- ---------------------------------------------------------------------------

-- Every registered point, with coordinates, as the server last sent it. Nil
-- until the editor has asked, and never filled for anybody who is not an
-- admin, because the server does not answer them.
Client.adminPoints = nil

function Client.receiveAdminPoints(arguments)
    Client.adminPoints = arguments and arguments.points or {}
    triggerEvent(Core.events.OnAdminPointsReceived, Client.adminPoints)
end

function Client.requestAdminPoints()
    Core.dispatch(Core.commands.adminList, {})
end

function Client.adminPort(id)
    Core.dispatch(Core.commands.adminPort, {
        id = id
    })
end

--- An empty label puts the registered one back.
function Client.adminRename(id, label)
    Core.dispatch(Core.commands.adminRename, {
        id = id,
        label = label or ""
    })
end

--- The console door to the server's admin actions: list, grant, where,
--- reload. The answer is printed to this client's console, as lines.
--- Checked for admin rights on the server like everything else here.
---
---   PhunTaxi.admin("reload")   read PhunTaxi.json again after a hand edit
function Core.admin(action, args)
    local payload = {}
    for k, v in pairs(args or {}) do
        payload[k] = v
    end
    payload.action = action
    Core.dispatch(Core.commands.admin, payload)
end

--- Everything below is saved to the store file on the server, so it
--- survives a wipe. See server/store.lua.
function Client.adminAddPoint(x, y, z, label)
    Core.dispatch(Core.commands.adminAddPoint, {
        x = x,
        y = y,
        z = z,
        label = label
    })
end

function Client.adminRemovePoint(id)
    Core.dispatch(Core.commands.adminRemovePoint, {
        id = id
    })
end

function Client.adminRestorePoint(id)
    Core.dispatch(Core.commands.adminRestorePoint, {
        id = id
    })
end

function Client.adminSetKind(id, discovery)
    Core.dispatch(Core.commands.adminSetKind, {
        id = id,
        discovery = discovery
    })
end

--- By square, from the context menu, or by point id, from the editor.
function Client.adminKeepPhone(args)
    Core.dispatch(Core.commands.adminKeepPhone, args)
end

function Client.adminReleasePhone(id)
    Core.dispatch(Core.commands.adminReleasePhone, {
        id = id
    })
end

--- Reached from the admin panel and the debug menu; see client_admin.lua.
function Client.openEditor()
    local Editor = require "PhunTaxi/ui/editor"
    Editor.open(getPlayer())
end

--- Open the spawn point picker.
--
-- Required on first use rather than at the top of this file, because the
-- picker requires this file and a require cycle in Kahlua hands one side a
-- half built module.
function Client.openPicker()
    local Picker = require "PhunTaxi/ui/picker"
    Picker.open(getPlayer())
end

--- Where a taxi from the phone at `from` ({x, y, z}) can go: every phone
--- this character knows but that one. Nil before the first payload, which
--- is not the same as nowhere.
function Client.taxiRows(from)
    if not Client.points then
        return nil
    end
    local here = Core.phoneKey(from.x, from.y, from.z)
    local out = {}
    for _, point in ipairs(Client.points) do
        if point.known and point.phone and point.phone ~= here then
            table.insert(out, point)
        end
    end
    return out
end

--- Open the picker as a taxi from the phone at `from` ({x, y, z, fx, fy},
--- the phone's square and the one in front): only known phones, and the
--- fare on the button.
function Client.openTaxi(from)
    local Picker = require "PhunTaxi/ui/picker"
    Picker.open(getPlayer(), from)
end

return Client
