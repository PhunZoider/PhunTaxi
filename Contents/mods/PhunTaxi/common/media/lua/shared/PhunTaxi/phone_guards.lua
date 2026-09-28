require "PhunSpawn/core"
require "PhunSpawn/phones"
local Core = PhunSpawn

-- ---------------------------------------------------------------------------
-- Our phones stay where they are and stay standing, unless an admin says
-- otherwise.
--
-- A phone is a spawn point recorded against its square, so moving it breaks
-- the point and destroying it deletes it. The guards cover every way vanilla
-- has of doing either to a plain IsoObject:
--
--   pick up, rotate, dismantle   ISMoveableSpriteProps.canPickUpMoveable and
--                                canScrapObject for the cursor and the menu,
--                                ISMoveablesAction.isValid for the action
--   sledgehammer                 ISDestroyCursor.canDestroy for the cursor,
--                                ISDestroyStuffAction.isValid for the action
--   being driven into            the tiles' HitByCar property, taken off
--
-- SHARED, unlike PhunInteriors' client_guards, because in B42 the server
-- completes these timed actions itself and asks isValid as it does. A guard
-- only a client runs is one a modified client does not run.
--
-- "Admin mode" is the character's own movables or build cheat, the switches
-- vanilla already honours for exactly these actions. So an admin is not held
-- back by being an admin, only by leaving the switch off, which is also how
-- they see what a player sees. PhunInteriors learned the other half of that:
-- its tent guard once honoured the cheat and its first test ran with the
-- switch on, so it looked like no guard at all. Turn the switch OFF to test.
--
-- Installed from OnInitGlobalModData rather than at file load, because every
-- class hooked here is vanilla lua that may not have loaded before our shared
-- folder, and OnInitGlobalModData fires everywhere once all lua is in.
-- ---------------------------------------------------------------------------

local installed = false

--- Is this character allowed to move or destroy one of our phones?
function Core.phoneAdminMode(character)
    if ISMoveableDefinitions and ISMoveableDefinitions.cheat then
        return true
    end
    if ISBuildMenu and ISBuildMenu.cheat then
        return true
    end
    if character then
        if character.isMovablesCheat and character:isMovablesCheat() then
            return true
        end
        if character.isBuildCheat and character:isBuildCheat() then
            return true
        end
    end
    return false
end

local function isPhoneSprite(sprite)
    return sprite ~= nil and Core.phoneFacing(sprite:getName()) ~= nil
end

local function isPhoneObject(object)
    return object ~= nil and object.getSprite ~= nil and isPhoneSprite(object:getSprite())
end

-- The moveable cursor asks canPickUpMoveable every frame it hovers, so the
-- explanation is throttled. The refusal itself is not.
local NOTE_MS = 3000
local lastNote = 0

local function refuse(character)
    if not character or not character.setHaloNote or isServer() then
        return
    end
    local now = getTimestampMs()
    if now - lastNote < NOTE_MS then
        return
    end
    lastNote = now
    character:setHaloNote(getText("IGUI_PhunSpawn_PhoneBolted"), 255, 180, 60, 300)
end

--- Take HitByCar off every phone sprite of ours, so a car stops against a
--- phone rather than flattening it. BaseVehicle looks the property up by
--- name, and PropertyContainer has unset(String) for exactly that.
function Core.hardenPhoneSprites()
    for name in pairs(Core.phoneSpriteSet()) do
        local sprite = getSprite(name)
        local props = sprite and sprite:getProperties()
        if props and props:has("HitByCar") then
            props:unset("HitByCar")
        end
    end
end

function Core.installPhoneGuards()
    if installed then
        return
    end
    installed = true

    Core.hardenPhoneSprites()

    if ISMoveableSpriteProps then
        local baseCanPickUp = ISMoveableSpriteProps.canPickUpMoveable
        function ISMoveableSpriteProps:canPickUpMoveable(character, square, object)
            if isPhoneSprite(self.sprite) and not Core.phoneAdminMode(character) then
                refuse(character)
                return false
            end
            return baseCanPickUp(self, character, square, object)
        end

        local baseCanScrap = ISMoveableSpriteProps.canScrapObject
        function ISMoveableSpriteProps:canScrapObject(character)
            local result, chance, perkName = baseCanScrap(self, character)
            if isPhoneSprite(self.sprite) and not Core.phoneAdminMode(character) then
                result = result or {}
                result.canScrap = false
                return result, 0, perkName
            end
            return result, chance, perkName
        end
    else
        Core.logLn("ISMoveableSpriteProps not loaded; the phone pickup guard is off")
    end

    -- The action itself, for a request that did not come through our cursor.
    -- Placing is allowed: a phone put down somewhere is just a phone.
    if ISMoveablesAction then
        local baseIsValid = ISMoveablesAction.isValid
        function ISMoveablesAction:isValid()
            if self.mode ~= "place" and not Core.phoneAdminMode(self.character) then
                local props = self.moveProps
                if (props and isPhoneSprite(props.sprite)) or
                    (self.origSpriteName and Core.phoneFacing(self.origSpriteName)) then
                    refuse(self.character)
                    self:stop()
                    return false
                end
            end
            return baseIsValid(self)
        end
    else
        Core.logLn("ISMoveablesAction not loaded; the phone move guard is off")
    end

    if ISDestroyStuffAction then
        local baseIsValid = ISDestroyStuffAction.isValid
        function ISDestroyStuffAction:isValid()
            if isPhoneObject(self.item) and not Core.phoneAdminMode(self.character) then
                refuse(self.character)
                return false
            end
            return baseIsValid(self)
        end
    else
        Core.logLn("ISDestroyStuffAction not loaded; the phone sledgehammer guard is off")
    end

    -- Client only in practice (it is a cursor), but it lives in vanilla's
    -- server folder, which a client loads too.
    if ISDestroyCursor then
        local baseCanDestroy = ISDestroyCursor.canDestroy
        function ISDestroyCursor:canDestroy(object)
            if isPhoneObject(object) and not Core.phoneAdminMode(self.character) then
                return false
            end
            return baseCanDestroy(self, object)
        end
    end
end

Events.OnInitGlobalModData.Add(Core.installPhoneGuards)

return Core
