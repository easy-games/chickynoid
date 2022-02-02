--!strict

--[=[
    @class ChickynoidClient
    @client

    Client namespace for the Chickynoid package.
]=]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local ClientChickynoid = require(script.ClientChickynoid)

local DefaultConfigs = require(script.Parent.DefaultConfigs)
local Types = require(script.Parent.Types)
local TableUtil = require(script.Parent.Vendor.TableUtil)

local Enums = require(script.Parent.Enums)
local EventType = Enums.EventType

local ChickynoidClient = {}
ChickynoidClient.localChickynoid = nil
ChickynoidClient.snapshots = {}
ChickynoidClient.estimatedServerTime = -1
ChickynoidClient.characters = {}
ChickynoidClient.localFrame = 0

local ClientConfig = TableUtil.Copy(DefaultConfigs.DefaultClientConfig, true)

function ChickynoidClient:SetConfig(config: Types.IClientConfig)
    local newConfig = TableUtil.Reconcile(config, DefaultConfigs.DefaultClientConfig)
    ClientConfig = newConfig
    print("Set client config to:", ClientConfig)
end

--[=[
    Setup default connections for the client-side Chickynoid. This mostly
    includes handling character spawns/despawns, for both the local player
    and other players.

    Everything done:
    - Listen for our own character spawn event and construct a LocalChickynoid
    class.
    - TODO

    @error "Remote cannot be found" -- Thrown when the client cannot find a remote after waiting for it for some period of time.
    @yields
]=]
function ChickynoidClient:Setup()
    
    
    local eventHandler = {}
    eventHandler[EventType.ChickynoidAdded] = function(event)
        local position = event.position
        print("Chickynoid spawned at", position)
        
        
       
        
        if (self.localChickynoid == nil) then
            self.localChickynoid = ClientChickynoid.new(position, ClientConfig)
        end
        --Force the position
        self.localChickynoid.simulation.state.pos = position
        
            
        
    end
    
    -- EventType.State
    eventHandler[EventType.State] = function(event)
        
        if self.localChickynoid and event.lastConfirmed then
            self.localChickynoid:HandleNewState(event.state, event.lastConfirmed)
        end
    end
    
    -- EventType.Snapshot
    
    eventHandler[EventType.Snapshot] = function(event)
        
        event.t = event.f * (1/60)
        --Todo: correct this over time
        if (self.estimatedServerTime == -1 or math.abs(self.estimatedServerTime - event.t) > 0.3 ) then     
            self.estimatedServerTime = event.t
        end
            
        table.insert(self.snapshots, event)
        
        --we need like 2 or 3..
        if (#self.snapshots > 10) then
            table.remove(self.snapshots,1)
        end        
        
    end
    
    

    
    script.Parent.RemoteEvent.OnClientEvent:Connect(function(event)
        local func = eventHandler[event.t]
        if (func~=nil) then
            func(event)
        end
    end)
    
    --ALL OF THE CODE IN HERE IS ASTONISHINGLY TEMPORARY!
    
    RunService.Heartbeat:Connect(function(dt)
        
        local serverHz = 20
        self.localFrame += 1
        
        if (self.localChickynoid) then
            self.localChickynoid:Heartbeat(dt)
        end
        
        
        --This will drift after a while
        if (self.estimatedServerTime ~= -1) then
            self.estimatedServerTime += dt
        end
        
        --Generate a worldview
        --Generate a new worldstate
        
        local searchPoint = self.estimatedServerTime - ((1/60) * ((60/serverHz)+4))
        
        --print("searchpoint", searchPoint)
        
        local last = nil
        local prev = self.snapshots[1]
        for key,value in pairs(self.snapshots) do
            
            if (value.t > searchPoint) then
                last = value
                break
            end
            prev = value
        end
        
        if (prev and last) then
             --print(prev.t,last.t)
            
            
            for userId,lastData in pairs(last.charData) do
                
                local prevData = prev.charData[userId]
                
                if (prevData == nil) then
                    continue
                end
                
                local frac = (searchPoint-prev.t) * serverHz
                --print("Frac", frac)
                local interp =  self.localChickynoid.simulation.characterData:Interpolate(prevData,lastData, frac)
                
                
                local character = self.characters[userId]
                
                --Add the character
                if (character == nil) then
                    local instance = Instance.new("Part")
                    instance.Anchored = true
                    instance.Parent = game.Workspace
                    instance.Color = Color3.new(1,0.5,0.2)
                    instance.Size = Vector3.new(3,5,3)
                    local record = {}
                    record.instance = instance
                    character = record
                    self.characters[userId] = record
                end
                
                character.frame = self.localFrame
                character.instance.Position = interp.pos
              

            end
        else
            if (#self.snapshots>0) then
                print("last known is", self.snapshots[#self.snapshots].t)
                self.estimatedServerTime =  self.snapshots[#self.snapshots].t
            end
            
        end
        
        --Remove the character
        for key,value in pairs(self.characters) do
            if value.frame ~= self.localFrame then
                value.instance:Destroy()
                self.characters[key] = nil
            end
        end
    end)
end

return ChickynoidClient
