local module = {}
module.history = {}
module.temporaryPositions = {}

local path = script.Parent.Parent
local Enums = require(path.Enums)

function module:Setup(server)
    module.server = server
end

function module:WritePlayerPositions(serverTime)
    local players = self.server:GetPlayers()

    local snapshot = {}
    snapshot.serverTime = serverTime
    snapshot.players = {}
    for _, playerRecord in pairs(players) do
        if playerRecord.chickynoid then
            local record = {}
            record.position = playerRecord.chickynoid.simulation.state.pos
            snapshot.players[playerRecord.userId] = record
        end
    end

    table.insert(self.history, snapshot)

    for counter = #self.history, 1, -1 do
        local oldSnapshot = self.history[counter]

        --only keep 1s of history
        if oldSnapshot.serverTime < serverTime - 1 then
            table.remove(self.history, counter)
        end
    end
end

function module:PushPlayerPositionsToTime(playerRecord, serverTime)
    local players = self.server:GetPlayers()

    if #self.temporaryPositions > 0 then
        warn("POP not called after a PushPlayerPositionsToTime")
    end

    --find the two records
    local prevRecord = nil
    local nextRecord = nil
    for counter = #self.history - 1, 1, -1 do
        if self.history[counter].serverTime < serverTime then
            prevRecord = self.history[counter]
            nextRecord = self.history[counter + 1]
            break
        end
    end

    if prevRecord == nil then
        warn("Could not find antilag time for ", serverTime)
        return
    end

    local frac = ((serverTime - prevRecord.serverTime) / (nextRecord.serverTime - prevRecord.serverTime))
    local debugFlag = self.server.flags.DEBUG_ANTILAG
    if debugFlag == true then
        print(
            "Prev time ",
            prevRecord.serverTime,
            " Next Time ",
            nextRecord.serverTime,
            " des time ",
            serverTime,
            " frac ",
            frac
        )
    end

    self.temporaryPositions = {}
    for userId, prevPlayerRecord in pairs(prevRecord.players) do
        if userId == playerRecord.userId then
            continue --Dont move us
        end

        local nextPlayerRecord = nextRecord.players[userId]
        if nextPlayerRecord == nil then
            continue
        end

        local otherPlayerRecord = players[userId]
        if otherPlayerRecord == nil then
            continue
        end

        if otherPlayerRecord.chickynoid == nil then
            continue
        end
        if otherPlayerRecord.chickynoid.hitBox then
            local oldPos = otherPlayerRecord.chickynoid.hitBox.Position
            self.temporaryPositions[userId] = oldPos --Store it

            local pos = prevPlayerRecord.position:Lerp(nextPlayerRecord.position, frac)

            --place it just how it was when the server saw it
            otherPlayerRecord.chickynoid.hitBox.Position = pos

            if debugFlag == true then
                local event = {}
                event.t = Enums.EventType.DebugBox
                event.pos = pos
                playerRecord:SendEventToClient(event)
            end
        end
    end
end

function module:Pop()
    local players = self.server:GetPlayers()

    for userId, pos in pairs(self.temporaryPositions) do
        local playerRecord = players[userId]

        if playerRecord and playerRecord.chickynoid then
            if playerRecord.chickynoid.hitBox then
                playerRecord.chickynoid.hitBox.Position = pos
            end
        end
    end

    self.temporaryPositions = {}
end

return module
