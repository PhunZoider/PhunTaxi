if isServer() then
    return
end
require "PhunTaxi/points"
require "PhunTaxi/tools"
require "PhunTaxi/interiors"
require "PhunTaxi/phone_guards"
require "PhunTaxi/defaults"
require "PhunTaxi/client_main"
require "PhunTaxi/client_context"
require "PhunTaxi/client_taxi"
local Core = PhunTaxi
local Commands = require "PhunTaxi/client_commands"

-- Set once setup has sent the first character's playerSetup; see
-- OnCreatePlayer below.
local setupDone = false

local function setup()
    Events.OnTick.Remove(setup)
    Core.refreshSettings()

    -- On a dedicated server the registry that decides anything lives server
    -- side, but the client needs its own copy for menu and drawing
    -- decisions, so open registration here as well. In single player both
    -- this and server_events run, and the guard inside openRegistration is
    -- what stops every point registering twice.
    Core.openRegistration()
    triggerEvent(Core.events.OnReady, Core)

    -- Deferred to the first OnTick rather than run at file load, so anything
    -- vanilla we wrap is certain to exist. The same deferral PhunInteriors
    -- uses for its destroy guards and its tracker, where installing early
    -- meant the hook silently did nothing.
    Core.dispatch(Core.commands.playerSetup, {})
    setupDone = true
end

Events.OnTick.Add(setup)

-- A character made after a death. Lua is not reloaded for one, so setup
-- above never runs again, and playerSetup is the server's only sight of a new
-- character: without this one is left on the landing square, never put in
-- the arrival room, with no leash and no taxi to reach. The first character
-- of a load is setup's, which is why this waits for setup to have run.
--
-- A tick later rather than inside the event, for getPlayer() and the
-- connection to be the new character's by the time it is sent.
local function newCharacter()
    Events.OnTick.Remove(newCharacter)
    Core.dispatch(Core.commands.playerSetup, {})
end
Events.OnCreatePlayer.Add(function(playerIndex, player)
    if setupDone then
        Events.OnTick.Remove(newCharacter)
        Events.OnTick.Add(newCharacter)
    end
end)

Events.OnServerCommand.Add(function(module, command, arguments)
    if module == Core.name and Commands[command] then
        Commands[command](arguments or {})
    end
end)
