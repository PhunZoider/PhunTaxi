if isServer() then
    return
end
require "TimedActions/ISBaseTimedAction"
require "PhunTaxi/client_main"
require "PhunTaxi/phones"
local Core = PhunTaxi
local Client = Core.client

-- ---------------------------------------------------------------------------
-- Walking to a phone, picking it up, and hearing one ring.
--
-- The action is the felt part only. The server checks the player is standing
-- at the phone when the request arrives, whatever the client did to get
-- there, so walking is what makes the request succeed rather than what
-- permits it.
--
-- Client only, like PhunMart's open shop action: nothing here changes the
-- world, so there is nothing for the server to complete, and perform() just
-- sends the request. Kept on Client rather than as a global class, which is
-- the house rule and PhunMart2's pattern too.
-- ---------------------------------------------------------------------------

--- Whether this player already knows the phone, from their points payload.
--- Before the first payload nothing is known. By its square, which a known
--- point with a phone carries, since a place registered with a phone keeps
--- its own id.
function Client.knowsPhone(phone)
    local square = phone and phone:getSquare()
    if not square then
        return false
    end
    local key = Core.phoneKey(square:getX(), square:getY(), square:getZ())
    for _, point in ipairs(Client.points or {}) do
        if point.phone == key then
            return point.known == true
        end
    end
    return false
end

local Action = ISBaseTimedAction:derive("PhunTaxiUsePhoneAction")
Client.UsePhoneAction = Action

-- Roughly the Loot animation once through: long enough to read as picking up
-- a receiver, short enough not to be a chore at every phone.
local USE_TICKS = 60

--- Still standing where a phone of ours is. It can be carried off by an admin
--- or swapped out between queueing and arriving.
function Action:isValid()
    local square = self.phone and self.phone:getSquare()
    if not square then
        return false
    end
    local sprite = self.phone:getSprite()
    return sprite ~= nil and Core.phoneFacing(sprite:getName()) ~= nil
end

function Action:waitToStart()
    self.character:faceThisObject(self.phone)
    return self.character:shouldBeTurning()
end

function Action:update()
    self.character:faceThisObject(self.phone)
end

function Action:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Mid")
    -- A phone that is ringing for us stops when we answer it.
    Client.stopRing()
end

function Action:stop()
    ISBaseTimedAction.stop(self)
end

function Action:perform()
    -- A phone already known has nothing to give, and the server would only say
    -- so. Calling a taxi from one goes straight to the picker.
    if not Client.knowsPhone(self.phone) then
        Client.usePhone(self.phone)
    end
    if self.andThen then
        self.andThen(self.phone)
    end
    ISBaseTimedAction.perform(self)
end

--- `andThen(phone)`, when given, runs once the phone has been used: calling
--- a taxi is picking up the phone and then choosing where to go.
function Action:new(character, phone, andThen)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.phone = phone
    o.andThen = andThen
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = character:isTimedActionInstant() and 1 or USE_TICKS
    return o
end

--- Walk to the phone, then use it.
--
-- To the square in FRONT of the phone when that is free, since that is where
-- the phone is used from and where its spawn point is. Anything else, a car
-- parked there say, falls back to vanilla's nearest free adjacent square,
-- which may be beside the phone; the server's reach allows for that.
-- Walk to `front` when it is free, else to anywhere beside `square`. False
-- when there is no way there.
local function walkTo(player, square, front)
    if player:getCurrentSquare() == front then
        return true
    end
    if front and front:isFree(false) then
        ISTimedActionQueue.add(ISWalkToTimedAction:new(player, front))
        return true
    end
    return luautils.walkAdj(player, square, true)
end

function Client.queueUsePhone(player, phone, andThen)
    local square = phone and phone:getSquare()
    if not player or not square then
        return
    end
    local facing = Core.phoneFacing(phone:getSprite():getName())
    local fx, fy = Core.phoneFront(square:getX(), square:getY(), facing)
    local front = getCell():getGridSquare(fx, fy, square:getZ())

    ISTimedActionQueue.clear(player)
    if not walkTo(player, square, front) then
        return
    end
    ISTimedActionQueue.add(Action:new(player, phone, andThen))
end

--- Walk up to a phone and call a taxi from it, then open the picker as a
--- taxi from there. Only offered on a phone already found (client_context.lua),
--- and the server refuses a ride from one that is not.
function Client.queueTaxi(player, phone)
    Client.queueUsePhone(player, phone, function(used)
        local square = used:getSquare()
        local facing = Core.phoneFacing(used:getSprite():getName())
        local fx, fy = Core.phoneFront(square:getX(), square:getY(), facing)
        Client.openTaxi({
            x = square:getX(),
            y = square:getY(),
            z = square:getZ(),
            fx = fx,
            fy = fy
        })
    end)
end

-- ---------------------------------------------------------------------------
-- Building a phone from a kit. The action is the felt cost; the server checks
-- everything, places the phone and spends the kit, and a refusal costs
-- nothing but the time.
-- ---------------------------------------------------------------------------

local BUILD_TICKS = 400

local BuildAction = ISBaseTimedAction:derive("PhunTaxiBuildPhoneAction")
Client.BuildPhoneAction = BuildAction

function BuildAction:isValid()
    return self.kit ~= nil and self.character:getInventory():containsID(self.kit:getID())
end

function BuildAction:waitToStart()
    self.character:faceLocation(self.square:getX(), self.square:getY())
    return self.character:shouldBeTurning()
end

function BuildAction:update()
    self.character:faceLocation(self.square:getX(), self.square:getY())
end

function BuildAction:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Mid")
end

function BuildAction:stop()
    ISBaseTimedAction.stop(self)
end

function BuildAction:perform()
    Client.buildPhone(self.square, self.facing, self.kit)
    ISBaseTimedAction.perform(self)
end

function BuildAction:new(character, square, facing, kit)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.square = square
    o.facing = facing
    o.kit = kit
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = character:isTimedActionInstant() and 1 or BUILD_TICKS
    return o
end

--- Walk to the square the phone will face, then build it: that is where a
--- caller will stand, and where a traveller will land.
function Client.queueBuildPhone(player, square, facing, kit)
    if not player or not square or not kit then
        return
    end
    local fx, fy = Core.phoneFront(square:getX(), square:getY(), facing)
    local front = getCell():getGridSquare(fx, fy, square:getZ())
    ISInventoryPaneContextMenu.transferIfNeeded(player, kit)
    if not walkTo(player, square, front) then
        return
    end
    ISTimedActionQueue.add(BuildAction:new(player, square, facing, kit))
end

-- ---------------------------------------------------------------------------
-- The ring. Decided and played here, with no help from the server.
--
-- The client already knows what it needs. Every phone it loads comes through
-- LoadGridsquare, and every phone this player has used is in their points
-- payload with the key of its square (Core.phoneKey) as `phone`. So a phone of
-- ours whose square is not in the payload is one they do not know, and it
-- rings.
--
-- Vanilla phones are noted as well as ours. The server swaps a phone the
-- first time anybody loads its square, which is usually as somebody walks up,
-- and a client can load the square before the swapped phone reaches it. So
-- what stands on a square is asked again at ring time, not trusted from load.
--
-- A phone somebody put down from an item rings too. The server records it
-- the first time it is used or its square loads, so picking it up works.
-- ---------------------------------------------------------------------------

-- key -> {x, y, z}: squares seen holding a phone, ours or vanilla. Pruned at
-- ring time, when a square turns out to be unloaded or phoneless.
local spots = {}

local function noteSquare(square)
    if not Core.settings.PhoneRing or not square then
        return
    end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local sprite = objects:get(i):getSprite()
        local name = sprite and sprite:getName()
        if name and (Core.phoneFacing(name) or Core.phoneTargetFacing(name)) then
            local x, y, z = square:getX(), square:getY(), square:getZ()
            spots[Core.phoneKey(x, y, z)] = {
                x = x,
                y = y,
                z = z
            }
            return
        end
    end
end

-- true: one of ours stands there now. false: a phone, but not ours (yet).
-- nil: the square is unloaded or has no phone at all, so forget it.
local function standing(spot)
    local square = getCell():getGridSquare(spot.x, spot.y, spot.z)
    if not square then
        return nil
    end
    local objects = square:getObjects()
    local vanilla = false
    for i = 0, objects:size() - 1 do
        local sprite = objects:get(i):getSprite()
        local name = sprite and sprite:getName()
        if name then
            if Core.phoneFacing(name) then
                return true
            end
            vanilla = vanilla or Core.phoneTargetFacing(name) ~= nil
        end
    end
    return vanilla and false or nil
end

-- Squares of phones that have already had their ring this session. A phone
-- rings once, long, and then not again until the player logs back in: a short
-- ring every few minutes reads as a clock, and one phone ringing off the hook
-- reads as somebody trying to get through.
local rung = {}

-- Known phones and phones that have had their ring, which are the same thing
-- as far as choosing what to ring goes. By square key.
local function skipKeys()
    local out = {}
    for _, point in ipairs(Client.points or {}) do
        if point.known and point.phone then
            out[point.phone] = true
        end
    end
    for key in pairs(rung) do
        out[key] = true
    end
    return out
end

local ringing = nil

local function tickRing()
    if ringing and getTimestampMs() >= ringing.stopAt then
        Client.stopRing()
    end
end

function Client.stopRing()
    if not ringing then
        return
    end
    -- The sound loops, so it must be stopped outright. By its handle, and
    -- then everything on the emitter: a free emitter is only handed out
    -- empty, so nothing else of anybody's is playing on it.
    ringing.emitter:stopSound(ringing.sound)
    ringing.emitter:stopAll()
    ringing = nil
    Events.OnTick.Remove(tickRing)
end

--- Ring the phone on a square, from the square itself, for `ms` or ringMs.
function Client.ringPhone(x, y, z, ms)
    Client.stopRing()
    local emitter = getWorld():getFreeEmitter(x + 0.5, y + 0.5, z or 0)
    if not emitter then
        return
    end
    ringing = {
        emitter = emitter,
        sound = emitter:playSound(Core.phones.ringSound),
        stopAt = getTimestampMs() + (ms or Core.phones.ringMs or 4000)
    }
    Events.OnTick.Add(tickRing)
end

--- Ring the nearest phone this player has not used, if one is in range.
--
-- Waits for the first points payload: before it the client cannot tell a
-- known phone from an unknown one, and ringing every phone in town on login
-- is the wrong way to find out.
function Client.ringNearest()
    local player = getPlayer()
    if not Core.settings.PhoneRing or ringing or not player or not Client.points then
        return
    end
    local spot = Core.phoneToRing(spots, skipKeys(), player:getX(), player:getY(),
        Core.settings.PhoneRingRange or 0, standing)
    if spot then
        rung[Core.phoneKey(spot.x, spot.y, spot.z)] = true
        Client.ringPhone(spot.x, spot.y, spot.z)
    end
end

Events.LoadGridsquare.Add(noteSquare)
-- Asked every in game minute, so a phone starts ringing soon after the player
-- comes into range rather than after they have walked past it. Cheap: a phone
-- that has rung is skipped, and only so many are ever in range.
Events.EveryOneMinute.Add(Client.ringNearest)

return Client
