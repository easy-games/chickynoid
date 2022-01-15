local Types = require(script.Parent.Types)

local DefaultConfigs = {}

local SimulationConfig: Types.ISimulationConfig = {
    raycastWhitelist = { workspace },
    feetHeight = -1.9,
    stepSize = 2.1,
}

local ServerConfig: Types.IServerConfig = {
    simulationConfig = SimulationConfig,
}

local ClientConfig: Types.IServerConfig = {
    simulationConfig = SimulationConfig,
}

DefaultConfigs.DefaultSimulationConfig = SimulationConfig
DefaultConfigs.DefaultServerConfig = ServerConfig
DefaultConfigs.DefaultClientConfig = ClientConfig

return DefaultConfigs
