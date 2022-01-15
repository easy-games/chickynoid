--!strict

--[=[
    @class ChickynoidServer
    @server

    Server namespace for the Chickynoid package.
]=]

local DefaultConfigs = require(script.Parent.DefaultConfigs)
local Types = require(script.Parent.Types)
local TableUtil = require(script.Parent.Vendor.TableUtil)

local ServerCharacter = require(script.ServerCharacter)
local ServerTransport = require(script.ServerTransport)

local ChickynoidServer = {}
local ServerConfig = TableUtil.Copy(DefaultConfigs.DefaultServerConfig, true)

function ChickynoidServer.Setup()
    -- TODO: Move this into a proper public method
    ServerTransport._getRemoteEvent()
end

function ChickynoidServer.SetConfig(config: Types.IServerConfig)
    local newConfig = TableUtil.Reconcile(config, DefaultConfigs.DefaultServerConfig)
    ServerConfig = newConfig
    print("Set server config to:", ServerConfig)
end

--[=[
    Spawns a new Chickynoid character for the specified player.

    @param player Player -- The player to spawn this Chickynoid for.
    @return ServerCharacter -- New character instance made for this player.
]=]
function ChickynoidServer.SpawnForPlayerAsync(player: Player)
    local character = ServerCharacter.new(player, ServerConfig)
    return character
end

return ChickynoidServer
