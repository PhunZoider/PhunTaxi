if isServer() then
    return
end
require "PhunTaxi/client_main"
require "PhunTaxi/phones"
require "PhunTaxi/client_phone"
require "PhunTaxi/client_build"
require "PhunTaxi/tools"
require "PhunTaxi/phone_guards"
require "ISUI/ISTextBox"
require "ISUI/ISToolTip"
local Core = PhunTaxi
local uiTools = require "PhunTaxi/ui/ui_utils"
local Client = Core.client

-- ---------------------------------------------------------------------------
-- The context menu.
--
-- Every option is a request rather than an action. Whatever it asks for is
-- decided server side, so the menu offering something is a convenience and
-- never a permission.
-- ---------------------------------------------------------------------------

local function onOpenPicker()
    Client.openPicker()
end

-- Walks over and picks it up; see client_phone.lua.
local function onUsePhone(player, phone)
    Client.queueUsePhone(player, phone)
end

local function phoneOn(square)
    local objects = square and square:getObjects()
    if not objects then
        return nil
    end
    for i = 0, objects:size() - 1 do
        local candidate = objects:get(i)
        local sprite = candidate:getSprite()
        if sprite and Core.phoneFacing(sprite:getName()) then
            return candidate
        end
    end
    return nil
end

-- Squares in front of a clicked one, in screen terms below it: a tall object
-- on one of these is drawn over the clicked square, and where it overlaps
-- the wall behind it the picker can hand us the wall instead.
local IN_FRONT = {{1, 0}, {0, 1}, {1, 1}}

-- One of our phones on the clicked squares, or else just in front of one,
-- and the object that was clicked. Squares, because what lands in
-- worldObjects depends on which pixel was clicked, and a phone is a small
-- target. In front as well, because clicking the upper half of a phone
-- against a wall picked the wall, on the square behind. The clicked object
-- is what Project Viewpoint's first person menu wants to see among an
-- option's arguments, which is not the phone when the wall was picked.
local function findPhone(worldObjects)
    for _, obj in ipairs(worldObjects) do
        local phone = phoneOn(obj.getSquare and obj:getSquare())
        if phone then
            return phone, obj
        end
    end
    for _, obj in ipairs(worldObjects) do
        local square = obj.getSquare and obj:getSquare()
        if square then
            for _, d in ipairs(IN_FRONT) do
                local phone = phoneOn(getCell():getGridSquare(square:getX() + d[1], square:getY() + d[2], square:getZ()))
                if phone then
                    return phone, obj
                end
            end
        end
    end
    return nil
end

local function isTaxi(obj)
    local sprite = obj.getSprite and obj:getSprite()
    return sprite ~= nil and Core.isTaxiTile(sprite:getName())
end

-- A taxi tile (Core.isTaxiTile), clicked or on a clicked square, is the taxi.
-- Returns the tile, the clicked object itself when it is one: Project
-- Viewpoint's first person menu keeps an option only when an argument IS the
-- object under the crosshair (see PhunInteriors' CLAUDE.md).
local function onTaxi(worldObjects)
    for _, obj in ipairs(worldObjects) do
        if isTaxi(obj) then
            return obj
        end
    end
    for _, obj in ipairs(worldObjects) do
        local square = obj.getSquare and obj:getSquare()
        if square then
            local objects = square:getObjects()
            for i = 0, objects:size() - 1 do
                if isTaxi(objects:get(i)) then
                    return objects:get(i)
                end
            end
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Setting a world up, for an admin: a new phone with its spawn point, a bare
-- spawn point, or storing the phone that was clicked. All are saved to the
-- store file on the server, so they survive a wipe. In a submenu so an
-- admin's menu does not grow by three lines for every click.
--
-- Only once the admin has turned it on, with the editor's "Setup menu"
-- button (Client.setupMenu). An admin playing normally does not want setup
-- options on every right click, so it starts off each session. It used to
-- follow admin mode (the movables or build cheat), and that tied it to a
-- switch admins flip for other reasons. On top of that the player must be an
-- admin or moderator on a server, or in debug mode in single player, where
-- tools.isAdmin says yes to everybody. The server checks rights again.
-- ---------------------------------------------------------------------------

local function isSetupAdmin(player)
    if not Client.setupMenu then
        return false
    end
    if Core.isLocal and not (isDebugEnabled and isDebugEnabled()) then
        return false
    end
    return Core.tools.isAdmin(player)
end

--- Which way a phone on `square` faces so that it faces the player: the
--- player stands in front of it, which is where the spawn point goes. The
--- longer axis wins on a diagonal. Nil when the player is on the square.
local function facingToward(player, square)
    local dx = math.floor(player:getX()) - square:getX()
    local dy = math.floor(player:getY()) - square:getY()
    if dx == 0 and dy == 0 then
        return nil
    end
    if math.abs(dx) >= math.abs(dy) then
        return dx > 0 and "E" or "W"
    end
    return dy > 0 and "S" or "N"
end

local function disable(option, text)
    option.notAvailable = true
    local tooltip = ISToolTip:new()
    tooltip:initialise()
    tooltip:setVisible(false)
    tooltip.description = text
    option.toolTip = tooltip
end

-- The clicked square, and the object it was read off, which is what Project
-- Viewpoint's first person menu needs to see among an option's arguments.
local function clickedSquare(worldObjects)
    for _, obj in ipairs(worldObjects) do
        local square = obj.getSquare and obj:getSquare()
        if square then
            return square, obj
        end
    end
    return nil
end

-- Any phone, ours or vanilla: keeping a vanilla one swaps it for ours.
local function findAnyPhone(worldObjects)
    for _, obj in ipairs(worldObjects) do
        local square = obj.getSquare and obj:getSquare()
        if square then
            local objects = square:getObjects()
            for i = 0, objects:size() - 1 do
                local sprite = objects:get(i):getSprite()
                local name = sprite and sprite:getName()
                if name and (Core.phoneFacing(name) or Core.phoneTargetFacing(name)) then
                    return square
                end
            end
        end
    end
    return nil
end

local function onAddPoint(player, square)
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local width = math.floor(360 * uiTools.FONT_SCALE)
    local height = math.floor(180 * uiTools.FONT_SCALE)
    local modal = ISTextBox:new((getCore():getScreenWidth() - width) / 2, (getCore():getScreenHeight() - height) / 2,
        width, height, getText("IGUI_PhunTaxi_Prompt_AddPoint", x .. ", " .. y .. ", " .. z), "", nil,
        function(_, button)
            if button.internal ~= "OK" then
                return
            end
            local text = (button.parent.entry:getText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if text ~= "" then
                Client.adminAddPoint(x, y, z, text)
            end
        end)
    modal:initialise()
    modal:addToUIManager()
end

local function onKeepPhone(player, square, facing)
    Client.adminKeepPhone({
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        facing = facing
    })
end

local function addSetupMenu(player, context, worldObjects)
    local square = clickedSquare(worldObjects)
    if not square then
        return
    end
    local parent = context:addOption(getText("ContextMenu_PhunTaxi_Setup"))
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(parent, sub)

    -- A phone already there is stored as it is. Otherwise one can be put
    -- there, facing the admin, and its spawn point goes where they stand.
    local phoneSquare = findAnyPhone(worldObjects)
    if phoneSquare then
        sub:addOption(getText("ContextMenu_PhunTaxi_KeepPhone"), player, onKeepPhone, phoneSquare)
    else
        local facing = facingToward(player, square)
        local option = sub:addOption(getText("ContextMenu_PhunTaxi_AddPhone"), player, onKeepPhone, square,
            facing)
        if not facing then
            disable(option, getText("IGUI_PhunTaxi_Tip_StandBeside"))
        end
    end
    sub:addOption(getText("ContextMenu_PhunTaxi_AddPoint"), player, onAddPoint, square)
end

--- "Install pay phone", for a player carrying a kit. It picks up the build
--- cursor (client_build.lua), where the phone is placed and turned; whether
--- it may go there is the server's call.
local function addBuildOption(player, context, worldObjects)
    if not Core.settings.AllowBuiltPoints then
        return
    end
    if not player:getInventory():getFirstTypeRecurse(Core.consts.phoneKitItem) then
        return
    end
    local _, clicked = clickedSquare(worldObjects)
    -- The clicked object trails, ignored by startBuildCursor, so the option
    -- survives in Viewpoint's first person menu.
    context:addOption(getText("ContextMenu_PhunTaxi_BuildPhone"), player, Client.startBuildCursor, clicked)
end

-- The same, from the kit in the inventory.
Events.OnFillInventoryObjectContextMenu.Add(function(playerIndex, context, items)
    local player = getSpecificPlayer(playerIndex)
    if not player or not Core.settings.AllowBuiltPoints then
        return
    end
    for _, entry in ipairs(items) do
        local item = type(entry) == "table" and entry.items and entry.items[1] or entry
        if item and item.getFullType and item:getFullType() == Core.consts.phoneKitItem then
            context:addOption(getText("ContextMenu_PhunTaxi_BuildPhone"), player, Client.startBuildCursor)
            return
        end
    end
end)

Events.OnFillWorldObjectContextMenu.Add(function(playerIndex, context, worldObjects, test)
    local player = getSpecificPlayer(playerIndex)
    if not player then
        return
    end

    -- Offered for any phone of ours this player does not know yet, including
    -- one an admin just put down. Whether it is a spawn point is the server's
    -- answer.
    -- Every option here carries the clicked object last, ignored by its
    -- handler, for Viewpoint's first person menu (see findPhone).
    local phone, clicked = findPhone(worldObjects)
    if phone then
        if not Client.knowsPhone(phone) then
            context:addOption(getText("ContextMenu_PhunTaxi_UsePhone"), player, onUsePhone, phone, clicked)
        end
        -- Fast travel, when the server has it on, from a phone this player
        -- has already found: picking it up comes first. The fare and every
        -- check are the server's; see server/rides.lua.
        if Core.settings.TaxiFastTravel and Client.knowsPhone(phone) then
            context:addOption(getText("ContextMenu_PhunTaxi_CallTaxi"), player, Client.queueTaxi, phone, clicked)
        end
        -- The builder's own phone. The stamp is only what this menu reads;
        -- the server checks its record. Taking it down walks up and picks up
        -- the receiver first, which costs nothing and gets the builder there.
        if phone:getModData()[Core.consts.phoneOwnerKey] == Core.accountKey(player) then
            context:addOption(getText("ContextMenu_PhunTaxi_TakeDown"), player, Client.queueUsePhone, phone,
                Client.takeDownPhone, clicked)
        end
    else
        addBuildOption(player, context, worldObjects)
    end

    -- The picker. For a player it is the taxi: offered only on a taxi tile,
    -- which stands in the spawn room, so a new character takes a ride out.
    -- An admin with the setup menu on gets it anywhere, as a map of every
    -- point they know. Whether Go works is the server's
    -- decision, not this menu's.
    -- The taxi rides along as a trailing argument onOpenPicker ignores, so
    -- the option survives in Viewpoint's first person menu.
    local taxi = onTaxi(worldObjects)
    if taxi then
        context:addOption(getText("ContextMenu_PhunTaxi_Taxi"), player, onOpenPicker, taxi)
    elseif isSetupAdmin(player) then
        context:addOption(getText("ContextMenu_PhunTaxi_Points"), player, onOpenPicker)
    end

    if not test and isSetupAdmin(player) then
        addSetupMenu(player, context, worldObjects)
    end
end)
