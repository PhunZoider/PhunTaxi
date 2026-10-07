if isServer() then
    return
end
require "PhunTaxi/core"
local Core = PhunTaxi

-- ---------------------------------------------------------------------------
-- UI constants and the few helpers the vendored list panel and the picker
-- reach for.
--
-- A TRIMMED copy of PhunInteriors' client/PhunInteriors/ui/ui_utils.lua,
-- itself trimmed from PhunMart2's. What came across is the font constants,
-- wrapText, truncate and the confirm dialog, which is everything anything
-- here calls, plus PhunMart2's freeCursorWhileShown for Project Viewpoint. The widget builders stayed behind: nothing here builds a form.
--
-- FONT_SCALE is the whole reason these are constants rather than literals. PZ
-- lets a player pick a UI font size, so a panel laid out in pixels is right at
-- one setting and unreadable at the others; every size below is derived from
-- the measured height of the small font instead.
-- ---------------------------------------------------------------------------

local tools = {}
Core.ui.tools = tools

tools.FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
tools.FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
tools.FONT_HGT_LARGE = getTextManager():getFontHeight(UIFont.Large)
tools.BUTTON_HGT = tools.FONT_HGT_SMALL + 6
tools.FONT_SCALE = tools.FONT_HGT_SMALL / 14
tools.HEADER_HGT = tools.FONT_HGT_MEDIUM + 2 * 2

function tools.truncate(text, maxWidth, font)
    if getTextManager():MeasureStringX(font, text) <= maxWidth then
        return text
    end
    local t = text
    while #t > 0 and getTextManager():MeasureStringX(font, t .. "...") > maxWidth do
        t = t:sub(1, -2)
    end
    return t .. "..."
end

-- Word-wrap text into lines fitting within maxWidth.
function tools.wrapText(text, maxWidth, font)
    local lines = {}
    local current = ""
    for word in text:gmatch("%S+") do
        local test = current == "" and word or (current .. " " .. word)
        if getTextManager():MeasureStringX(font, test) <= maxWidth then
            current = test
        else
            if current ~= "" then
                table.insert(lines, current)
            end
            current = word
        end
    end
    if current ~= "" then
        table.insert(lines, current)
    end
    return lines
end

function tools.confirm(text, onYes, owner)
    local lines = tools.wrapText(text, math.floor(340 * tools.FONT_SCALE), UIFont.Small)
    local w = math.floor(380 * tools.FONT_SCALE)
    local h = math.max(math.floor(130 * tools.FONT_SCALE),
        #lines * tools.FONT_HGT_SMALL + math.floor(90 * tools.FONT_SCALE))
    local modal = ISModalDialog:new((getCore():getScreenWidth() - w) / 2, (getCore():getScreenHeight() - h) / 2, w, h,
        table.concat(lines, "\n"), true, owner, function(_, button)
            if button.internal == "YES" and onYes then
                onYes()
            end
        end)
    modal:initialise()
    modal:addToUIManager()
    return modal
end

--- Frees the mouse from first person mods while `panel` is showing. Copied
--- from PhunMart2's ui_utils.lua.
---
--- Viewpoint (workshop 3809306528) captures the mouse for looking and only lets
--- it go when `UIManager.isModalVisible()`, which is true while any visible
--- element, or any child of one, has capture set. Capture on the window itself
--- would route every click on the screen to it, inventory included, so a
--- zero-size child holds it instead: a parent only hands a captured child the
--- events that already landed on the parent. The child consumes nothing, so
--- the controls under the cursor still get every click. Hiding the window
--- hides it too, and the mouse goes back to looking.
function tools.freeCursorWhileShown(panel)
    local sentinel = ISUIElement:new(0, 0, 0, 0)
    sentinel:initialise()
    sentinel:instantiate()
    sentinel.javaObject:setConsumeMouseEvents(false)
    local pass = function()
        return false
    end
    sentinel.onMouseDown = pass
    sentinel.onMouseUp = pass
    sentinel.onMouseMove = pass
    sentinel.onMouseWheel = pass
    sentinel.onRightMouseDown = pass
    sentinel.onRightMouseUp = pass
    sentinel.onMouseDoubleClick = pass
    sentinel:setCapture(true)
    panel:addChild(sentinel)
    return sentinel
end

return tools
