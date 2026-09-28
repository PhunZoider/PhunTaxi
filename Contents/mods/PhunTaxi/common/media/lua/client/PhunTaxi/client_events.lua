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
end

Events.OnTick.Add(setup)

Events.OnServerCommand.Add(function(module, command, arguments)
    if module == Core.name and Commands[command] then
        Commands[command](arguments or {})
    end
end)
