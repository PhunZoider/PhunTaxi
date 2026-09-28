if isServer() then
    return
end
require "PhunSpawn/client_main"
require "PhunSpawn/phones"
require "PhunSpawn/client_phone"
require "PhunSpawn/tools"
require "PhunSpawn/phone_guards"
require "ISUI/ISTextBox"
require "ISUI/ISToolTip"
local Core = PhunSpawn
local uiTools = require "PhunSpawn/ui/ui_utils"
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

-- One of our phones among the clicked objects or on their squares. Squares as
-- well, because what lands in worldObjects depends on which pixel was
-- clicked, and a phone is a small target.
local function findPhone(worldObjects)
    for _, obj in ipairs(worldObjects) do
        local square = obj.getSquare and obj:getSquare()
        if square then
            local objects = square:getObjects()
            for i = 0, objects:size() - 1 do
                local candidate = objects:get(i)
                local sprite = candidate:getSprite()
                if sprite and Core.phoneFacing(sprite:getName()) then
                    return candidate
                end
            end
        end
    end
    return nil
end

-- A taxi tile (Core.isTaxiTile), clicked or on a clicked square, is the taxi.
local function onTaxi(worldObjects)
    for _, obj in ipairs(worldObjects) do
        local square = obj.getSquare and obj:getSquare()
        if square then
            local objects = square:getObjects()
            for i = 0, objects:size() - 1 do
                local sprite = objects:get(i):getSprite()
                if sprite and Core.isTaxiTile(sprite:getName()) then
                    return true
                end
            end
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Setting a world up, for an admin: a new phone with its spawn point, a bare
-- spawn point, or storing the phone that was clicked. All are saved to the
-- store file on the server, so they survive a wipe. In a submenu so an
-- admin's menu does not grow by three lines for every click.
--
-- Only in ADMIN MODE: the movables or build cheat, the same switch the phone
-- guards read (Core.phoneAdminMode). An admin playing normally does not want
-- setup options on every right click, and turning admin mode on is already
-- what they do to move things about. On top of that the player must be an
-- admin or moderator on a server, or in debug mode in single player, where
-- tools.isAdmin says yes to everybody. The server checks rights again.
-- ---------------------------------------------------------------------------

local function isSetupAdmin(player)
    if not Core.phoneAdminMode(player) then
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

local function clickedSquare(worldObjects)
    for _, obj in ipairs(worldObjects) do
        local square = obj.getSquare and obj:getSquare()
        if square then
            return square
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
        width, height, getText("IGUI_PhunSpawn_Prompt_AddPoint", x .. ", " .. y .. ", " .. z), "", nil,
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
    local parent = context:addOption(getText("ContextMenu_PhunSpawn_Setup"))
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(parent, sub)

    -- A phone already there is stored as it is. Otherwise one can be put
    -- there, facing the admin, and its spawn point goes where they stand.
    local phoneSquare = findAnyPhone(worldObjects)
    if phoneSquare then
        sub:addOption(getText("ContextMenu_PhunSpawn_KeepPhone"), player, onKeepPhone, phoneSquare)
    else
        local facing = facingToward(player, square)
        local option = sub:addOption(getText("ContextMenu_PhunSpawn_AddPhone"), player, onKeepPhone, square,
            facing)
        if not facing then
            disable(option, getText("IGUI_PhunSpawn_Tip_StandBeside"))
        end
    end
    sub:addOption(getText("ContextMenu_PhunSpawn_AddPoint"), player, onAddPoint, square)
end

--- "Install pay phone", for a player carrying a kit, on a square with no
--- phone. The phone faces the player, as the admin's does, and is greyed
--- out on their own square. Whether it may go there is the server's call;
--- this only shows the option when it could.
local function addBuildOption(player, context, worldObjects)
    if not Core.settings.AllowBuiltPoints then
        return
    end
    local kit = player:getInventory():getFirstTypeRecurse(Core.consts.phoneKitItem)
    local square = kit and clickedSquare(worldObjects)
    if not square or findAnyPhone(worldObjects) then
        return
    end
    local facing = facingToward(player, square)
    local option = context:addOption(getText("ContextMenu_PhunSpawn_BuildPhone"), player, Client.queueBuildPhone,
        square, facing, kit)
    if not facing then
        disable(option, getText("IGUI_PhunSpawn_Tip_StandBeside"))
    end
end

Events.OnFillWorldObjectContextMenu.Add(function(playerIndex, context, worldObjects, test)
    local player = getSpecificPlayer(playerIndex)
    if not player then
        return
    end

    -- Offered for any phone of ours, including one a player carried here from
    -- somewhere else. Whether it is a spawn point is the server's answer.
    local phone = findPhone(worldObjects)
    if phone then
        context:addOption(getText("ContextMenu_PhunSpawn_UsePhone"), player, onUsePhone, phone)
        -- Fast travel, when the server has it on. The fare and every check
        -- are the server's; see server/rides.lua.
        if Core.settings.TaxiFastTravel then
            context:addOption(getText("ContextMenu_PhunSpawn_CallTaxi"), player, Client.queueTaxi, phone)
        end
        -- The builder's own phone. The stamp is only what this menu reads;
        -- the server checks its record. Taking it down walks up and picks up
        -- the receiver first, which costs nothing and gets the builder there.
        if phone:getModData()[Core.consts.phoneOwnerKey] == Core.accountKey(player) then
            context:addOption(getText("ContextMenu_PhunSpawn_TakeDown"), player, Client.queueUsePhone, phone,
                Client.takeDownPhone)
        end
    else
        addBuildOption(player, context, worldObjects)
    end

    -- The picker. For a player it is the taxi: offered only on a taxi tile,
    -- which stands in the spawn room, so a new character takes a ride out.
    -- An admin in admin mode gets it anywhere, as a map of every point they
    -- know. Whether Go works is the server's decision, not this menu's.
    if onTaxi(worldObjects) then
        context:addOption(getText("ContextMenu_PhunSpawn_Taxi"), player, onOpenPicker)
    elseif isSetupAdmin(player) then
        context:addOption(getText("ContextMenu_PhunSpawn_Points"), player, onOpenPicker)
    end

    if not test and isSetupAdmin(player) then
        addSetupMenu(player, context, worldObjects)
    end
end)
