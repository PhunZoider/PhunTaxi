if isServer() then
    return
end
require "ISUI/ISCollapsableWindow"
require "ISUI/ISTextBox"
require "PhunSpawn/client_main"
local Core = PhunSpawn
local Client = Core.client
local tools = require "PhunSpawn/ui/ui_utils"
local ListPanel = require "PhunSpawn/ui/list_panel"
local MapPanel = require "PhunSpawn/ui/map_panel"

-- ---------------------------------------------------------------------------
-- The admin editor: every registered point, found or not, in one flat list on
-- the left, and the whole map on the right with a pin for each.
--
-- Select a point to see it on the map, then Go there, Rename it, or Reset its
-- name to the one it was registered with. A pay phone can be Kept, so it is
-- in the next world after a wipe, or Released. A point an admin added (from
-- the context menu's setup submenu) can have its Kind changed or be Removed.
-- Every one of those is saved to PhunSpawn.json on the server. Nothing here decides anything: the
-- server checks admin rights on every request, and a rename comes back as a
-- fresh list rather than being applied to this copy, so what the rows show is
-- what the server stored.
--
-- Deliberately not the picker with a flag. The picker draws a player's
-- payload, which withholds what they have not found, and is grouped by city
-- because a player is choosing a town first. An admin is looking for one
-- point by name, id or kind, so this is a flat, sortable, filterable list
-- over a different payload (Core.adminPayload).
-- ---------------------------------------------------------------------------

local FONT_SCALE = tools.FONT_SCALE
local PAD = math.max(10, math.floor(10 * FONT_SCALE))

-- ---------------------------------------------------------------------------
-- The list
-- ---------------------------------------------------------------------------

local EditorList = ListPanel:derive("PhunSpawnEditorList")

local function regionLabel(name)
    if not name or name == "" then
        return getText("IGUI_PhunSpawn_Elsewhere")
    end
    return name
end

local function kindLabel(discovery)
    return getText("IGUI_PhunSpawn_Kind_" .. tostring(discovery))
end

-- Squares, which is metres as far as anybody reading it is concerned. Flat,
-- ignoring z: the question is how far away across the map, and a floor
-- difference of one is not a walk.
local function distanceTo(player, point)
    if not player or not point.x or not point.y then
        return nil
    end
    local dx, dy = point.x - player:getX(), point.y - player:getY()
    return math.sqrt(dx * dx + dy * dy)
end

local function distanceLabel(distance)
    if not distance then
        return ""
    end
    if distance < 1000 then
        return tostring(math.floor(distance + 0.5)) .. "m"
    end
    return string.format("%.1fkm", distance / 1000)
end

function EditorList:new(x, y, width, height, player, editor)
    local o = ListPanel.new(self, x, y, width, height, player)
    o.editor = editor
    return o
end

function EditorList:createChildren()
    ListPanel.createChildren(self)
    self.list.doDrawItem = ListPanel.defaultDrawRow
    self.list:setOnMouseDownFunction(self, self.onRowClick)

    -- Flat, so every column can sort. The picker's cannot, because a sort
    -- would scatter its points away from the city rows they sit under.
    self:addListColumn(getText("IGUI_PhunSpawn_Col_Name"), 0, {
        text = function(d)
            return d.point.label
        end,
        -- A renamed point is tinted, so what has been customised on this
        -- save reads at a glance, and Reset has somewhere obvious to apply.
        color = function(d)
            if d.point.renamed then
                return 0.95, 0.8, 0.35
            end
            return nil
        end,
        sort = true
    })
    self:addListColumn(getText("IGUI_PhunSpawn_Col_Region"), 0.34, {
        text = function(d)
            return regionLabel(d.point.region)
        end,
        sort = true
    })
    self:addListColumn(getText("IGUI_PhunSpawn_Col_Kind"), 0.52, {
        -- Marked when it is in the store file, which is what survives a
        -- wipe: a point an admin added, or a phone they kept.
        text = function(d)
            if d.point.saved then
                return getText("IGUI_PhunSpawn_Kind_Saved", kindLabel(d.point.discovery))
            end
            return kindLabel(d.point.discovery)
        end,
        sort = true
    })
    self:addListColumn(getText("IGUI_PhunSpawn_Col_Where"), 0.66, {
        text = function(d)
            local p = d.point
            return tostring(p.x) .. ", " .. tostring(p.y) .. ", " .. tostring(p.z or 0)
        end
    })
    -- From wherever the admin is standing now, so the text follows them as
    -- they move or port. The ORDER is taken when the list is sorted, which is
    -- on a refresh or a header click, not every frame: rows that reshuffle
    -- under the mouse cannot be clicked.
    self:addListColumn(getText("IGUI_PhunSpawn_Col_Distance"), 0.87, {
        text = function(d)
            return distanceLabel(distanceTo(self.player, d.point))
        end,
        sort = function(d)
            return distanceTo(self.player, d.point) or math.huge
        end,
        align = "right"
    })
    -- Nearest first. "Which phone is this" is usually "the one near me".
    self._sortColumn = 5
    self._sortDesc = false

    -- Phones get a tab of their own because there can be hundreds of them,
    -- and every other kind would be buried under them in "All".
    self:addFilterTabs({{
        key = "all",
        label = getText("IGUI_PhunSpawn_Tab_All")
    }, {
        key = Core.discovery.start,
        label = kindLabel(Core.discovery.start)
    }, {
        key = Core.discovery.explore,
        label = kindLabel(Core.discovery.explore)
    }, {
        key = Core.discovery.used,
        label = kindLabel(Core.discovery.used)
    }, {
        key = "other",
        label = getText("IGUI_PhunSpawn_Tab_Other")
    }})

    self.portButton = self:addBottomButton(getText("IGUI_PhunSpawn_Btn_Port"), self.onPortClick, true)
    self.renameButton = self:addBottomButton(getText("IGUI_PhunSpawn_Btn_Rename"), self.onRenameClick, true)
    self.resetButton = self:addBottomButton(getText("IGUI_PhunSpawn_Btn_ResetName"), self.onResetClick, false)
    -- Keep or Release for a phone, Kind and Remove for a point an admin
    -- added. Enabled by row in prerender, since each means something for one
    -- sort of row only.
    self.keepButton = self:addBottomButton(getText("IGUI_PhunSpawn_Btn_Release"), self.onKeepClick, false)
    self.kindButton = self:addBottomButton(getText("IGUI_PhunSpawn_Btn_Kind"), self.onKindClick, false)
    self.removeButton = self:addBottomButton(getText("IGUI_PhunSpawn_Btn_Remove"), self.onRemoveClick, false)
end

local function isPhone(point)
    return point ~= nil and point.discovery == Core.discovery.used
end

-- A point an admin added (or wrote into the file by hand). A kept phone is
-- saved too, but it is kept and released, not removed.
local function isAdded(point)
    return point ~= nil and point.saved == true and not isPhone(point)
end

-- The order Kind steps through. The three a point with nothing on the map
-- can be found by.
local KIND_CYCLE = {Core.discovery.start, Core.discovery.explore, Core.discovery.granted}

local function nextKind(discovery)
    for i, kind in ipairs(KIND_CYCLE) do
        if kind == discovery then
            return KIND_CYCLE[(i % #KIND_CYCLE) + 1]
        end
    end
    return Core.discovery.explore
end

function EditorList:rowInFilterTab(d, tabKey)
    local discovery = d.point.discovery
    if tabKey == "all" then
        return true
    end
    if tabKey == "other" then
        return discovery ~= Core.discovery.start and discovery ~= Core.discovery.explore and discovery ~=
                   Core.discovery.used
    end
    return discovery == tabKey
end

--- The id is searchable as well as the label, since an admin reading a log
--- or a console listing has the id and not the name.
function EditorList:getFilterText(d)
    local p = d.point
    return p.label .. " " .. p.id .. " " .. regionLabel(p.region) .. " " .. (p.shippedLabel or "")
end

function EditorList:refreshList()
    self:clearList()
    local count, renamed, saved = 0, 0, 0
    for _, point in ipairs(Client.adminPoints or {}) do
        count = count + 1
        if point.renamed then
            renamed = renamed + 1
        end
        if point.saved then
            saved = saved + 1
        end
        self:addListItem(point.label, {
            key = point.id,
            point = point
        })
    end
    self:applyFilter()

    if Client.adminPoints == nil then
        self.description = getText("IGUI_PhunSpawn_Desc_Loading")
    else
        self.description = getText("IGUI_PhunSpawn_Desc_Editor", tostring(count), tostring(renamed), tostring(saved))
    end

    if self.editor then
        self.editor:onListRefreshed()
    end
end
-- Hooked by the vendored panel to OnPointsReceived. Harmless here, since this
-- rebuilds from the admin copy, and it keeps an open editor current if a
-- player payload lands at the same time as a rename.
EditorList.refresh = EditorList.refreshList

function EditorList:selectedPoint()
    local d = self:selectedRow()
    return d and d.point or nil
end

function EditorList:onRowClick(d)
    if d then
        self.editor:onPointSelected(d.point, true)
    end
end

function EditorList:prerender()
    ListPanel.prerender(self)
    -- Reset only means something for a point that has been renamed.
    local point = self:selectedPoint()
    self.resetButton:setEnable(point ~= nil and point.renamed == true)
    if point and point.renamed then
        self.resetButton.tooltip = getText("IGUI_PhunSpawn_Tip_ResetName", point.shippedLabel or "")
    else
        self.resetButton.tooltip = nil
    end

    self.keepButton:setEnable(isPhone(point))
    local keepTitle = getText(point and point.saved and "IGUI_PhunSpawn_Btn_Release" or "IGUI_PhunSpawn_Btn_Keep")
    if self.keepButton.title ~= keepTitle then
        self.keepButton:setTitle(keepTitle)
    end
    self.keepButton.tooltip = isPhone(point) and
                                  getText(point.saved and "IGUI_PhunSpawn_Tip_Release" or "IGUI_PhunSpawn_Tip_Keep") or
                                  nil

    self.kindButton:setEnable(isAdded(point))
    self.kindButton.tooltip = isAdded(point) and
                                  getText("IGUI_PhunSpawn_Tip_Kind", kindLabel(nextKind(point.discovery))) or nil
    self.removeButton:setEnable(isAdded(point))
end

function EditorList:onKeepClick()
    local point = self:selectedPoint()
    if not isPhone(point) then
        return
    end
    if point.saved then
        Client.adminReleasePhone(point.id)
    else
        Client.adminKeepPhone({
            id = point.id
        })
    end
end

function EditorList:onKindClick()
    local point = self:selectedPoint()
    if isAdded(point) then
        Client.adminSetKind(point.id, nextKind(point.discovery))
    end
end

function EditorList:onRemoveClick()
    local point = self:selectedPoint()
    if isAdded(point) then
        Client.adminRemovePoint(point.id)
    end
end

function EditorList:onPortClick()
    local point = self:selectedPoint()
    if point then
        Client.adminPort(point.id)
    end
end

--- Ask for a new name, starting from the current one so a typo is a one
--- character fix rather than retyping the whole label.
function EditorList:onRenameClick()
    local point = self:selectedPoint()
    if not point then
        return
    end
    local width = math.floor(360 * FONT_SCALE)
    local height = math.floor(180 * FONT_SCALE)
    local modal = ISTextBox:new((getCore():getScreenWidth() - width) / 2, (getCore():getScreenHeight() - height) / 2,
        width, height, getText("IGUI_PhunSpawn_Prompt_Rename", point.id), point.label, self, function(_, button)
            if button.internal ~= "OK" then
                return
            end
            local text = button.parent.entry:getText() or ""
            -- Trimmed here as well as on the server, so a label typed with a
            -- trailing space is not sent as a change that is not one.
            text = text:gsub("^%s+", ""):gsub("%s+$", "")
            -- Empty is refused here rather than read as Reset. Clearing the
            -- box by accident should not quietly undo a rename; Reset is its
            -- own button for that.
            if text ~= "" and text ~= point.label then
                Client.adminRename(point.id, text)
            end
        end)
    modal:initialise()
    modal:addToUIManager()
end

function EditorList:onResetClick()
    local point = self:selectedPoint()
    if point and point.renamed then
        Client.adminRename(point.id, "")
    end
end

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------

local Editor = ISCollapsableWindow:derive("PhunSpawnEditor")
Core.ui.editor = Editor
-- One per split screen player, by player number.
Editor.instances = {}

Events[Core.events.OnAdminPointsReceived].Add(function()
    for _, instance in pairs(Editor.instances) do
        if instance:isVisible() then
            instance.list:refreshList()
        end
    end
end)

function Editor.open(player)
    if not player then
        return nil
    end
    local index = player:getPlayerNum()
    local instance = Editor.instances[index]
    if not instance then
        local core = getCore()
        local w = math.min(core:getScreenWidth() - 40, math.floor(1200 * FONT_SCALE))
        local h = math.min(core:getScreenHeight() - 40, math.floor(700 * FONT_SCALE))
        instance = Editor:new((core:getScreenWidth() - w) / 2, (core:getScreenHeight() - h) / 2, w, h, player)
        instance:initialise()
        instance:addToUIManager()
        Editor.instances[index] = instance
    else
        instance:setVisible(true)
        instance:bringToTop()
    end
    instance.list:refreshList()
    -- Always asked for again: a phone swapped in or a rename by another admin
    -- since the last look would otherwise be missing. The answer lands in
    -- refreshList through OnAdminPointsReceived.
    Client.requestAdminPoints()
    return instance
end

function Editor:new(x, y, width, height, player)
    local o = ISCollapsableWindow.new(self, x, y, width, height)
    o.player = player
    o.playerIndex = player:getPlayerNum()
    o.resizable = false
    o.title = getText("IGUI_PhunSpawn_EditorTitle")
    o.viewPlaced = false
    return o
end

function Editor:createChildren()
    ISCollapsableWindow.createChildren(self)
    local top = self:titleBarHeight()
    local bottom = self:resizeWidgetHeight()
    local listW = math.max(math.floor(540 * FONT_SCALE), math.floor(self.width * 0.5))
    local contentH = self.height - top - bottom

    self.map = MapPanel:new(listW, top + PAD, self.width - listW - PAD, contentH - PAD * 2, self.playerIndex)
    self:addChild(self.map)
    -- The whole map, not the admin's own: a point is somewhere to inspect
    -- whether or not this character has ever walked there.
    self.map:initMap(false)
    self.map:setOnPick(self, self.onPinClicked)

    self.list = EditorList:new(0, top, listW, contentH, self.player, self)
    self.list:initialise()
    self.list:setShell(self)
    self:addChild(self.list)
end

--- Pins for every point. The map panel draws only points marked known, which
--- is the picker's rule; here every point is one an admin may see.
function Editor:onListRefreshed()
    if not self.map then
        return
    end
    local pins = {}
    for _, point in ipairs(Client.adminPoints or {}) do
        table.insert(pins, {
            id = point.id,
            label = point.label,
            region = point.region,
            x = point.x,
            y = point.y,
            z = point.z,
            known = true
        })
    end
    self.map:setPoints(pins)
    local point = self.list:selectedPoint()
    self.map:setSelected(point and point.id or nil, point and (point.region or "") or nil)

    if not self.viewPlaced and #pins > 0 then
        self.viewPlaced = true
        local b
        for _, pin in ipairs(pins) do
            if not b then
                b = {
                    x1 = pin.x,
                    y1 = pin.y,
                    x2 = pin.x,
                    y2 = pin.y
                }
            else
                b.x1 = math.min(b.x1, pin.x)
                b.y1 = math.min(b.y1, pin.y)
                b.x2 = math.max(b.x2, pin.x)
                b.y2 = math.max(b.y2, pin.y)
            end
        end
        self.map:showBounds(b)
    end
end

function Editor:onPointSelected(point, move)
    self.map:setSelected(point and point.id or nil, point and (point.region or "") or nil)
    if move and point then
        self.map:showPoint(point)
    end
end

function Editor:onPinClicked(pointId)
    if self.list:selectKey(pointId) then
        self:onPointSelected(self.list:selectedPoint(), false)
    end
end

function Editor:close()
    self:setVisible(false)
    self:removeFromUIManager()
    Editor.instances[self.playerIndex] = nil
end

return Editor
