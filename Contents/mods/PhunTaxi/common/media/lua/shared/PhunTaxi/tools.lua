require "PhunSpawn/core"
local Core = PhunSpawn

-- ---------------------------------------------------------------------------
-- Local utility surface.
--
-- These were previously borrowed from PhunLib. PhunLib is deprecated, so they
-- are folded in here, matching what PhunInteriors, PhunServer2 and PhunZones2
-- already do. Do not reintroduce a PhunLib dependency to get them back.
--
-- Keep this file to things that genuinely have no vanilla equivalent. It is
-- not a dumping ground.
-- ---------------------------------------------------------------------------

local tools = {}
Core.tools = tools

-- Wrapper for getOnlinePlayers that normalises SP, coop host and dedicated.
-- In SP there is one player and getOnlinePlayers is not the answer; on a
-- client we only ever care about the local split screen players.
--
-- Note the asymmetry that bites: this returns only local players on a client
-- and everyone on a server, so a caller reading players:get(0) for "where am
-- I standing" is correct on a listen server and wrong on a dedicated one with
-- more than one admin.
function tools.onlinePlayers(all)

    local onlinePlayers

    if Core.isLocal then
        onlinePlayers = ArrayList.new()
        local p = getPlayer()
        if p then
            onlinePlayers:add(p)
        end
    elseif all ~= false and isClient() then
        onlinePlayers = ArrayList.new()
        for i = 0, getOnlinePlayers():size() - 1 do
            local player = getOnlinePlayers():get(i)
            if player:isLocalPlayer() then
                onlinePlayers:add(player)
            end
        end
    else
        onlinePlayers = getOnlinePlayers()
    end

    return onlinePlayers
end

-- PZ's Lua sandbox does not expose next(), so an emptiness test has to go
-- through pairs. LuaJIT will not catch a next() call, because next exists
-- there; the game is where it fails.
function tools.isEmpty(t)
    if not t then
        return true
    end
    for _ in pairs(t) do
        return false
    end
    return true
end

-- A copy nothing else holds a reference into.
--
-- Worth having before there is an override layer, because the failure a
-- shallow copy causes is invisible: the snapshot a revert rebuilds from ends
-- up sharing its sub tables with the live record, so the first edit writes
-- through into it and revert appears to work while changing nothing.
--
-- Metatables are deliberately not carried. Everything copied here is plain
-- data out of a registry table or a decoded JSON document, and a copy that
-- kept a metatable would be copying behaviour, which is not what any caller
-- means.
function tools.deepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for key, item in pairs(value) do
        out[key] = tools.deepCopy(item)
    end
    return out
end

-- Structural equality, used to decide whether an edit actually changed
-- anything. Storing a customisation identical to the shipped value is how a
-- file fills up with entries that do nothing and a record reads as customised
-- when it is stock.
function tools.deepEquals(a, b)
    if a == b then
        return true
    end
    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end
    for key, item in pairs(a) do
        if not tools.deepEquals(item, b[key]) then
            return false
        end
    end
    -- Both directions: the loop above is satisfied by `a` being a subset of
    -- `b`, so a key present only in `b` would compare equal.
    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end
    return true
end

-- Case insensitive by default. Returns nil when the player is not online,
-- which every caller here treats as "skip" and never as an error.
function tools.getPlayerByUsername(name, caseSensitive)
    if not name then
        return nil
    end
    local online = tools.onlinePlayers()
    if not online then
        return nil
    end
    local text = caseSensitive and name or string.lower(name)
    for i = 0, online:size() - 1 do
        local player = online:get(i)
        if player then
            local username = player:getUsername()
            if username then
                if (caseSensitive and username == name) or
                    (not caseSensitive and string.lower(username) == text) then
                    return player
                end
            end
        end
    end
    return nil
end

-- Admin test for a SPECIFIC player, because this is called server side to vet
-- an incoming command. The family's tools.isAdmin() asks about the local
-- machine, which is the wrong question on a dedicated server.
--
-- In single player there is no access level to speak of and it is the host's
-- own world, so the local player is allowed.
function tools.isAdmin(player)
    if Core.isLocal then
        return true
    end
    if player and player.getAccessLevel then
        local level = player:getAccessLevel()
        return level == "Admin" or level == "Moderator" or level == "admin" or level == "moderator"
    end
    return (isAdmin and isAdmin()) or (isDebugEnabled and isDebugEnabled()) or false
end

return tools
