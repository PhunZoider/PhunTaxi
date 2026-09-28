if isServer() then
    return
end
require "DebugUIs/DebugMenu/ISDebugMenu"
require "PhunSpawn/tools"
require "PhunSpawn/client_main"
local Core = PhunSpawn
local Client = Core.client

-- ---------------------------------------------------------------------------
-- Where the spawn point editor is reached from.
--
-- Two doors, the same two PhunInteriors and PhunMart2 use: the admin panel is
-- where an admin looks on a server, and the debug menu is where a single
-- player developer looks. Not the context menu, which every player opens all
-- day and which is already carrying three of our options. Both doors route
-- through one function, so the access rule cannot differ depending on which
-- one somebody happened to use.
--
-- The server re-checks admin rights on every command the editor sends, so
-- this is an entry point and not a gate. What it stops is the window opening
-- for somebody whose every button would then be refused.
--
-- Single player gets the editor only through the debug menu, which exists
-- only in debug mode. That is the rule the editor wants there: tools.isAdmin
-- says yes to everybody in SP, and the editor ports anywhere, which in an
-- ordinary game would be fast travel.
-- ---------------------------------------------------------------------------

local function openEditor()
    local player = getPlayer()
    if not player then
        return
    end
    if not Core.tools.isAdmin(player) then
        Client.notify({
            text = "IGUI_PhunSpawn_NotAdmin"
        })
        return
    end
    Client.openEditor()
end

-- Single player, and anyone with debug enabled.
local ISDebugMenu_setupButtons = ISDebugMenu.setupButtons
function ISDebugMenu:setupButtons()
    self:addButtonInfo("PhunSpawn", openEditor, "MAIN")
    ISDebugMenu_setupButtons(self)
end

-- The server admin panel.
--
-- The button is added BEFORE the base runs, which is what puts it in the grid:
-- vanilla's create() lays out every child it finds at the end, sorts them by
-- title and then places the close button beneath the lot. Adding afterwards
-- would leave ours sitting wherever it was put, on top of whatever was there.
local ISAdminPanelUI_create = ISAdminPanelUI.create
function ISAdminPanelUI:create()
    local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
    local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
    local UI_BORDER_SPACING = 10
    local BUTTON_HGT = FONT_HGT_SMALL + 6

    self.phunSpawnEditor = ISButton:new(UI_BORDER_SPACING + 1, FONT_HGT_MEDIUM + UI_BORDER_SPACING * 2 + 1, 200,
        BUTTON_HGT, getText("IGUI_PhunSpawn_EditorTitle"), self, openEditor)
    self.phunSpawnEditor.internal = ""
    self.phunSpawnEditor:initialise()
    self.phunSpawnEditor:instantiate()
    self.phunSpawnEditor.borderColor = self.buttonBorderColor
    self:addChild(self.phunSpawnEditor)

    ISAdminPanelUI_create(self)
end
