if isServer() then
    return
end
require "PhunSpawn/client_main"
require "PhunSpawn/client_phone"
local Core = PhunSpawn
local Client = Core.client
local Commands = {}

Commands[Core.commands.points] = function(arguments)
    Client.receivePoints(arguments)
end

Commands[Core.commands.unlocked] = function(arguments)
    Client.announceUnlock(arguments)
end

Commands[Core.commands.adminPoints] = function(arguments)
    Client.receiveAdminPoints(arguments)
end

Commands[Core.commands.notify] = function(arguments)
    Client.notify(arguments)
end

-- Lines meant for a log, printed as such. Kept separate from any payload
-- meant for a window, so nothing has to guess which it received.
Commands[Core.commands.adminResult] = function(arguments)
    if not arguments or not arguments.result then
        return
    end
    for _, line in ipairs(arguments.result) do
        print("[" .. Core.name .. "] " .. tostring(line))
    end
end

return Commands
