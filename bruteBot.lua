-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or nil
InAction = InAction or false -- Prevents the agent from taking multiple actions at once.
Logs = Logs or {}

-- Define colors for console output
colors = {
    red = "\27[31m",
    green = "\27[32m",
    reset = "\27[0m",
    gray = "\27[90m"
}

-- Function to add logs
function addLog(msg, text)
    Logs[msg] = Logs[msg] or {}
    table.insert(Logs[msg], text)
end

-- Checks if two points are within a given range.
-- @param x1, y1: Coordinates of the first point.
-- @param x2, y2: Coordinates of the second point.
-- @param range: The maximum allowed distance between the points.
-- @return: Boolean indicating if the points are within the specified range.
function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

-- Find a low-health opponent to ambush
function findAmbushTarget()
    local ambushTarget = nil
    local self = LatestGameState.Players[ao.id]

    for id, state in pairs(LatestGameState.Players) do
        if id == ao.id then
            goto continue
        end

        local opponent = state

        if opponent.health < 0.3 then
            ambushTarget = opponent
            break
        end

        ::continue::
    end

    return ambushTarget
end

-- Check if the player is within attack range
function isPlayerInAttackRange(player)
    local self = LatestGameState.Players[ao.id]

    return inRange(self.x, self.y, player.x, player.y, 1)
end

-- Attack the ambush target using 50% of energy
function attackAmbushTarget()
    local target = findAmbushTarget()

    if target then
        local attackEnergy = LatestGameState.Players[ao.id].energy * 0.5
        print(colors.red .. "Ambushing target with energy: " .. attackEnergy .. colors.reset)
        ao.send({ Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(attackEnergy) }) -- Attack with 50% of energy
        retreatAfterAttack() -- Immediately retreat after attacking
        return true
    end

    return false
end

-- Retreat after an attack to avoid retaliation
function retreatAfterAttack()
    local self = LatestGameState.Players[ao.id]
    local directions = { {x = 1, y = 0}, {x = -1, y = 0}, {x = 0, y = 1}, {x = 0, y = -1} }
    local direction = directions[math.random(1, #directions)]
    ao.send({ Target = Game, Action = "Move", X = self.x + direction.x, Y = self.y + direction.y })
    print(colors.green .. "Retreating after attack." .. colors.reset)
    InAction = false -- Reset InAction after moving
end

-- Move erratically to confuse opponents if surrounded
function moveErratically()
    local self = LatestGameState.Players[ao.id]
    local directions = { {x = 1, y = 0}, {x = -1, y = 0}, {x = 0, y = 1}, {x = 0, y = -1}, {x = 1, y = 1}, {x = -1, y = -1} }
    local direction = directions[math.random(1, #directions)]
    ao.send({ Target = Game, Action = "Move", X = self.x + direction.x, Y = self.y + direction.y })
    print(colors.gray .. "Moving erratically to confuse opponents." .. colors.reset)
    InAction = false -- Reset InAction after moving
end

-- Decide the next action based on player proximity, health, and energy.
function decideNextAction()
    if not attackAmbushTarget() then
        -- If no target found, move erratically to confuse opponents
        moveErratically()
    end
end

-- Handler to print game announcements and trigger game state updates.
Handlers.add(
    "PrintAnnouncements",
    Handlers.utils.hasMatchingTag("Action", "Announcement"),
    function(msg)
        if msg.Event == "Started-Waiting-Period" then
            ao.send({ Target = ao.id, Action = "AutoPay" })
        elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
            InAction = true  -- InAction logic added
            ao.send({ Target = Game, Action = "GetGameState" })
        elseif InAction then -- InAction logic added
            print("Previous action still in progress. Skipping.")
        end

        print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
    end
)

-- Handler to trigger game state updates.
Handlers.add(
    "GetGameStateOnTick",
    Handlers.utils.hasMatchingTag("Action", "Tick"),
    function()
        if not InAction then -- InAction logic added
            InAction = true  -- InAction logic added
            print(colors.gray .. "Getting game state..." .. colors.reset)
            ao.send({ Target = Game, Action = "GetGameState" })
        else
            print("Previous action still in progress. Skipping.")
        end
    end
)

-- Handler to automate payment confirmation when waiting period starts.
Handlers.add(
    "AutoPay",
    Handlers.utils.hasMatchingTag("Action", "AutoPay"),
    function(msg)
        print(colors.green .. "Auto-paying confirmation fees." .. colors.reset)
        ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1000" })
    end
)

-- Handler to update the game state upon receiving game state information.
Handlers.add(
    "UpdateGameState",
    Handlers.utils.hasMatchingTag("Action", "GameState"),
    function(msg)
        local json = require("json")
        LatestGameState = json.decode(msg.Data)
        ao.send({ Target = ao.id, Action = "UpdatedGameState" })
        print(colors.green .. "Game state updated. Print 'LatestGameState' for detailed view." .. colors.reset)
        print(colors.green .. "Energy: " .. LatestGameState.Players[ao.id].energy .. colors.reset)
    end
)

-- Handler to decide the next best action.
Handlers.add(
    "decideNextAction",
    Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
    function()
        if LatestGameState.GameMode ~= "Playing" then
            print(colors.green .. "Game not started." .. colors.reset)
            InAction = false -- InAction logic added
            return
        end
        print(colors.gray .. "Deciding next action." .. colors.reset)
        decideNextAction()
        ao.send({ Target = ao.id, Action = "Tick" })
    end
)

-- Handler to automatically attack when hit by another player.
Handlers.add(
    "ReturnAttack",
    Handlers.utils.hasMatchingTag("Action", "Hit"),
    function(msg)
        if not InAction then -- InAction logic added
            InAction = true  -- InAction logic added
            local playerEnergy = LatestGameState.Players[ao.id].energy
            if playerEnergy == nil then
                print(colors.red .. "Unable to read energy." .. colors.reset)
                ao.send({ Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy." })
            elseif playerEnergy == 0 then
                print(colors.red .. "Player has insufficient energy." .. colors.reset)
                ao.send({ Target = Game, Action = "Attack-Failed", Reason = "Player has no energy." })
            else
                print(colors.red .. "Returning attack." .. colors.reset)
                ao.send({ Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(playerEnergy) }) -- Attack with full energy
            end
            InAction = false -- InAction logic added
            ao.send({ Target = ao.id, Action = "Tick" })
        else
            print("Previous action still in progress. Skipping.")
        end
    end
)
