--[=[
    @class Types
    All types used by Chickynoid.
]=]

--[=[
    @interface ISimulationConfig
    @within Types
    .raycastWhitelist {BasePart} -- Raycast whitelist used for collision checks.
    .feetHeight number -- Players feet height. Height goes from -2.5 to +2.5 so any point below this number is considered the players feet. The distance between middle and feetHeight is "ledge".
    .stepSize number -- How big an object we can step over?

    The config passed to the Chickynoid [Simulation] class.
]=]
export type ISimulationConfig = {
    raycastWhitelist: { BasePart },
    feetHeight: number,
    stepSize: number,
}

--[=[
    @interface IServerConfig
    @within Types
    .simulationConfig ISimulationConfig -- The config passed to the Chickynoid [Simulation] class.
]=]
export type IServerConfig = {
    simulationConfig: ISimulationConfig,
}

--[=[
    @interface IClientConfig
    @within Types
    .simulationConfig ISimulationConfig -- The config passed to the Chickynoid [Simulation] class.
]=]
export type IClientConfig = {
    simulationConfig: ISimulationConfig,
}

return nil
