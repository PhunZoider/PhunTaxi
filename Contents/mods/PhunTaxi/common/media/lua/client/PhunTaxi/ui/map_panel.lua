if isServer() then
    return
end
require "ISUI/ISUIElement"
require "ISUI/Maps/ISMapDefinitions"
local Core = PhunSpawn
local tools = require "PhunSpawn/ui/ui_utils"

-- ---------------------------------------------------------------------------
-- The map half of the picker: the player's own world map, with a pin for
-- every point they know.
--
-- Built on UIWorldMap directly, the way vanilla's ISMiniMapInner is, rather
-- than on ISMiniMapInner itself. That one re-centres on the player in
-- prerenderHack every frame and toggles the full screen map on a click, and
-- both would have to be fought rather than used. What IS taken from vanilla
-- is the set up, call for call from ISWorldMap:initDataAndStyle, so this
-- looks like the map the player already knows and follows any mod that adds
-- map data.
--
-- Isometric is forced off. Pins and zoom-to-fit both read a screen rectangle
-- as a world rectangle, which is only true top down.
-- ---------------------------------------------------------------------------

local MapPanel = ISUIElement:derive("PhunSpawnMapPanel")

local FONT_HGT_SMALL = tools.FONT_HGT_SMALL
local PIN = math.max(10, math.floor(FONT_HGT_SMALL * 0.9))
local PIN_SELECTED = math.floor(PIN * 1.6)
-- Squares of margin round a fitted box, and the smallest box ever fitted. A
-- city with one known point is a box with no size, and fitting that exactly
-- lands on the maximum zoom, looking at one kerb.
local FIT_PAD = 40
local FIT_MIN_SPAN = 250
-- Zoom never goes past this when fitting or when centring on one point. The
-- player can still wheel in further by hand.
local FIT_MAX_ZOOM = 18.5
-- Below this zoom only the selected region's pins carry labels, or the
-- whole-map view is a wall of overlapping text.
local LABEL_ZOOM = 15
-- Pixels a press may travel and still count as a click rather than a drag.
local CLICK_SLOP = 4

local PIN_TEX = "media/textures/worldMap/circle_center.png"

function MapPanel:new(x, y, width, height, playerNum)
    local o = ISUIElement.new(self, x, y, width, height)
    o.playerNum = playerNum
    o.pins = {}
    o.selectedId = nil
    o.regionName = nil
    return o
end

function MapPanel:instantiate()
    self.javaObject = UIWorldMap.new(self)
    self.mapAPI = self.javaObject:getAPIv3()
    -- The player's own map item, so their symbols and notes are drawn on it.
    self.mapAPI:setMapItem(MapItem.getSingleton())
    self.javaObject:setX(self.x)
    self.javaObject:setY(self.y)
    self.javaObject:setWidth(self.width)
    self.javaObject:setHeight(self.height)
    self.javaObject:setAnchorLeft(self.anchorLeft)
    self.javaObject:setAnchorRight(self.anchorRight)
    self.javaObject:setAnchorTop(self.anchorTop)
    self.javaObject:setAnchorBottom(self.anchorBottom)
    self:createChildren()
end

--- Load the map data and style. Called once, after instantiate.
--
-- @param hideUnvisited  true draws only what this character has seen, which
--                       is what "the player's map" means. The picker passes
--                       false for a new character, who has seen nothing and
--                       would otherwise be choosing pins on a black square;
--                       vanilla's own spawn select shows the whole map too.
function MapPanel:initMap(hideUnvisited)
    local api = self.mapAPI
    MapUtils.initDefaultMapData(self)
    api:setBoundsFromWorld()
    MapUtils.initDefaultStreetData(self)
    MapUtils.initDefaultStyleV3(self)
    MapUtils.overlayPaper(self)

    api:setBoolean("Isometric", false)
    api:setBoolean("HideUnvisited", hideUnvisited == true)
    api:setBoolean("Players", true)
    api:setBoolean("RemotePlayers", false)
    api:setBoolean("Symbols", true)
    api:setBoolean("MiniMapSymbols", false)

    api:centerOn((api:getMinXInSquares() + api:getMaxXInSquares()) / 2,
        (api:getMinYInSquares() + api:getMaxYInSquares()) / 2)
end

-- ---------------------------------------------------------------------------
-- What to draw
-- ---------------------------------------------------------------------------

--- The pins. Known points with coordinates only: the payload withholds the
--- position of anything undiscovered, and there is nothing to draw for it.
function MapPanel:setPoints(points)
    local pins = {}
    for _, point in ipairs(points or {}) do
        if point.known and point.x and point.y then
            table.insert(pins, point)
        end
    end
    self.pins = pins
end

function MapPanel:setSelected(pointId, regionName)
    self.selectedId = pointId
    self.regionName = regionName
end

--- Where the owner wants to hear about a pin being clicked:
--- fn(target, pointId).
function MapPanel:setOnPick(target, fn)
    self.pickTarget = target
    self.onPick = fn
end

-- ---------------------------------------------------------------------------
-- Moving the view
-- ---------------------------------------------------------------------------

--- The highest zoom at which a world box centred on (cx, cy) still fits.
--
-- Asked of the map itself rather than worked out from a formula: the
-- uiToWorld overload that takes a zoom and a centre answers "what would be at
-- this pixel", which vanilla's own drag code relies on, so nothing here
-- depends on how PZ happens to relate zoom to scale. The answer is monotonic
-- in zoom, so a bisection settles it in a handful of calls.
function MapPanel:zoomToFit(cx, cy, spanX, spanY)
    local api = self.mapAPI
    local w, h = self.width, self.height
    local function fits(zoom)
        local wide = api:uiToWorldX(w, 0, zoom, cx, cy) - api:uiToWorldX(0, 0, zoom, cx, cy)
        local tall = api:uiToWorldY(0, h, zoom, cx, cy) - api:uiToWorldY(0, 0, zoom, cx, cy)
        return wide >= spanX and tall >= spanY
    end
    local lo, hi = 0, FIT_MAX_ZOOM
    if fits(hi) then
        return hi
    end
    for _ = 1, 16 do
        local mid = (lo + hi) / 2
        if fits(mid) then
            lo = mid
        else
            hi = mid
        end
    end
    return lo
end

--- Glide to show a world box, padded, and never narrower than FIT_MIN_SPAN.
function MapPanel:showBounds(b)
    if not b then
        return
    end
    local cx, cy = (b.x1 + b.x2) / 2, (b.y1 + b.y2) / 2
    local spanX = math.max(FIT_MIN_SPAN, (b.x2 - b.x1) + FIT_PAD * 2)
    local spanY = math.max(FIT_MIN_SPAN, (b.y2 - b.y1) + FIT_PAD * 2)
    self.mapAPI:transitionTo(cx, cy, self:zoomToFit(cx, cy, spanX, spanY))
end

--- Glide to one point, zooming in if the view is further out than a city.
function MapPanel:showPoint(point)
    if not point or not point.x then
        return
    end
    local zoom = self.mapAPI:getZoomF()
    local cityZoom = self:zoomToFit(point.x, point.y, FIT_MIN_SPAN, FIT_MIN_SPAN)
    self.mapAPI:transitionTo(point.x, point.y, math.max(zoom, cityZoom))
end

-- ---------------------------------------------------------------------------
-- Drawing
--
-- In render rather than prerender: the Java side draws the map and then calls
-- prerender, which is where vanilla lays its brightness overlay, so anything
-- drawn there would sit under that overlay.
-- ---------------------------------------------------------------------------

function MapPanel:prerender()
    MapUtils.renderDarkModeOverlay(self)
end

function MapPanel:pinAt(point)
    local api = self.mapAPI
    return api:worldToUIX(point.x, point.y), api:worldToUIY(point.x, point.y)
end

function MapPanel:render()
    ISUIElement.render(self)
    local tex = getTexture(PIN_TEX)
    local zoom = self.mapAPI:getZoomF()
    local labelAll = zoom >= LABEL_ZOOM

    self:setStencilRect(0, 0, self.width, self.height)

    -- Two passes, so the selected region's pins and the selected pin are
    -- drawn on top of everything else rather than wherever pairs put them.
    local selected
    for pass = 1, 2 do
        for _, point in ipairs(self.pins) do
            local inRegion = self.regionName ~= nil and (point.region or "") == self.regionName
            local isSelected = point.id == self.selectedId
            if isSelected then
                selected = point
            elseif (pass == 1) ~= inRegion then
                local sx, sy = self:pinAt(point)
                if sx > -PIN and sy > -PIN and sx < self.width + PIN and sy < self.height + PIN then
                    local a = inRegion and 1 or 0.55
                    if tex then
                        self:drawTextureScaled(tex, sx - PIN / 2, sy - PIN / 2, PIN, PIN, a, 0.15, 0.45, 0.85)
                    else
                        self:drawRect(sx - PIN / 2, sy - PIN / 2, PIN, PIN, a, 0.15, 0.45, 0.85)
                    end
                    if inRegion or labelAll then
                        self:drawLabel(point.label, sx + PIN / 2 + 2, sy - FONT_HGT_SMALL / 2, false)
                    end
                end
            end
        end
    end

    if selected then
        local sx, sy = self:pinAt(selected)
        if tex then
            self:drawTextureScaled(tex, sx - PIN_SELECTED / 2, sy - PIN_SELECTED / 2, PIN_SELECTED, PIN_SELECTED, 1,
                0.2, 0.8, 0.3)
        else
            self:drawRect(sx - PIN_SELECTED / 2, sy - PIN_SELECTED / 2, PIN_SELECTED, PIN_SELECTED, 1, 0.2, 0.8, 0.3)
        end
        self:drawLabel(selected.label, sx + PIN_SELECTED / 2 + 2, sy - FONT_HGT_SMALL / 2, true)
    end

    self:clearStencilRect()
    self:drawRectBorder(0, 0, self.width, self.height, 0.6, 0.4, 0.4, 0.4)
end

function MapPanel:drawLabel(text, x, y, strong)
    local w = getTextManager():MeasureStringX(UIFont.Small, text)
    self:drawRect(x - 2, y - 1, w + 4, FONT_HGT_SMALL + 2, strong and 0.85 or 0.6, 0, 0, 0)
    if strong then
        self:drawRectBorder(x - 2, y - 1, w + 4, FONT_HGT_SMALL + 2, 1, 0.2, 0.8, 0.3)
    end
    self:drawText(text, x, y, 1, 1, 1, 1, UIFont.Small)
end

-- ---------------------------------------------------------------------------
-- Mouse. Drag to pan and wheel to zoom, copied from ISMiniMapInner so it
-- handles the way the minimap does; a press that did not move is a click,
-- and a click on a pin picks it.
-- ---------------------------------------------------------------------------

function MapPanel:onMouseDown(x, y)
    self.dragging = true
    self.dragMoved = false
    self.dragStartX = x
    self.dragStartY = y
    self.dragStartCX = self.mapAPI:getCenterWorldX()
    self.dragStartCY = self.mapAPI:getCenterWorldY()
    self.dragStartZoomF = self.mapAPI:getZoomF()
    self.dragStartWorldX = self.mapAPI:uiToWorldX(x, y)
    self.dragStartWorldY = self.mapAPI:uiToWorldY(x, y)
    return true
end

function MapPanel:onMouseMove(dx, dy)
    if not self.dragging then
        return false
    end
    local mouseX = self:getMouseX()
    local mouseY = self:getMouseY()
    if not self.dragMoved and math.abs(mouseX - self.dragStartX) <= CLICK_SLOP and
        math.abs(mouseY - self.dragStartY) <= CLICK_SLOP then
        return true
    end
    self.dragMoved = true
    local api = self.mapAPI
    local worldX = api:uiToWorldX(mouseX, mouseY, self.dragStartZoomF, self.dragStartCX, self.dragStartCY)
    local worldY = api:uiToWorldY(mouseX, mouseY, self.dragStartZoomF, self.dragStartCX, self.dragStartCY)
    api:centerOn(self.dragStartCX + self.dragStartWorldX - worldX, self.dragStartCY + self.dragStartWorldY - worldY)
    return true
end

function MapPanel:onMouseMoveOutside(dx, dy)
    return self:onMouseMove(dx, dy)
end

function MapPanel:onMouseUp(x, y)
    if not self.dragging then
        return false
    end
    self.dragging = false
    if not self.dragMoved then
        local point = self:pinUnder(x, y)
        if point and self.onPick then
            self.onPick(self.pickTarget, point.id)
        end
    end
    return true
end

function MapPanel:onMouseUpOutside(x, y)
    self.dragging = false
end

function MapPanel:onMouseWheel(del)
    self.mapAPI:zoomAt(self:getMouseX(), self:getMouseY(), del)
    return true
end

--- The pin nearest a pixel, if one is close enough to have been meant.
function MapPanel:pinUnder(x, y)
    local best, bestDistance
    local reach = PIN_SELECTED * PIN_SELECTED
    for _, point in ipairs(self.pins) do
        local sx, sy = self:pinAt(point)
        local distance = (sx - x) * (sx - x) + (sy - y) * (sy - y)
        if distance <= reach and (not bestDistance or distance < bestDistance) then
            best, bestDistance = point, distance
        end
    end
    return best
end

return MapPanel
