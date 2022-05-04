local ChickynoidStyle = {}

--Defines a chickynoid, its data strucutres, and its associated methods for the API
--NOT YET IN USE!

--Defines the command structure used by this chickynoid
function ChickynoidStyle:DefineCommand()
    ChickynoidStyle.commandFields = {
        x = 0,
        y = 0,
        z = 0,
    }
end

function ChickynoidStyle:DefineCharacterData()
    --Character data is the information transferred from Simulation to all players to render the characterModel with
    ChickynoidStyle.characterDataFields = {
        pos = Vector3.zero,
        angle = 0,
        animCounter = 0,
        animNum = 0,
        stepUp = 0,
        flatSpeed = 0,
    }

    ChickynoidStyle.characterDataPackFunctions = {
        pos = "Vector3",
        angle = "Float16",
        animCounter = "Byte",
        animNum = "Byte",
        stepUp = "Float16",
        flatSpeed = "Float16",
    }

    ChickynoidStyle.characterDataLerpFunctions = {
        pos = "Lerp",
        angle = "AngleLerp",
        animCounter = "Raw",
        animNum = "Raw",
        stepUp = "NumberLerp",
        flatSpeed = "NumberLerp",
    }
end

--
function ChickynoidStyle:DefineSimulationState()
    ChickynoidStyle.simulationState = {
        pos = Vector3.zero,
        vel = Vector3.zero,
        jump = 0,
        angle = 0,
        targetAngle = 0,
        stepUp = 0,
        inAir = 0,
    }
end

ChickynoidStyle:DefineCommand()
ChickynoidStyle:DefineCharacterData()
ChickynoidStyle:DefineSimulationState()

return ChickynoidStyle
