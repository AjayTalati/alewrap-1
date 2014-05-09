
if not torch.data then
    require 'torchffi'
end

function alewrap.createEnv(romName, extraConfig)
    return alewrap.AleEnv(romName, extraConfig)
end

local WIDTH = 160
local HEIGHT = 210
local RAM_LENGTH = 128

-- Copies the config. An error is raised on unknown params.
local function updateDefaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            error("unsupported param: " .. k)
        end
        dst[k] = v
    end
end

local Env = torch.class('alewrap.AleEnv')
function Env:__init(romPath, extraConfig)
    self.config = {
        -- An additional reward signal can be provided
        -- after the end of one game.
        -- Note that many games don't change the score
        -- when loosing or gaining a life.
        gameOverReward=0,
        -- Screen display can be enabled.
        display=false,
        -- The RAM can be returned as an additional observation.
        enableRamObs=false,
    }
    updateDefaults(self.config, extraConfig)

    self.win = nil
    self.ale = alewrap.newAle(romPath)
    local obsShapes = {{HEIGHT, WIDTH}}
    if self.config.enableRamObs then
        obsShapes={{HEIGHT, WIDTH}, {RAM_LENGTH}}
    end
    self.envSpec = {
        nActions=18,
        obsShapes=obsShapes,
    }
end

-- Returns a description of the observation shapes
-- and of the possible actions.
function Env:getEnvSpec()
    return self.envSpec
end

-- Returns a list of observations.
-- The integer palette values are returned as the observation.
function Env:envStart()
    self.ale:resetGame()
    return self:_generateObservations()
end

-- Does the specified actions and returns the (reward, observations) pair.
-- Valid actions:
--     {torch.Tensor(zeroBasedAction)}
-- The action number should be an integer from 0 to 17.
function Env:envStep(actions)
    assert(#actions == 1, "one action is expected")
    assert(actions[1]:nElement() == 1, "one discrete action is expected")

    if self.ale:isGameOver() then
        self.ale:resetGame()
        -- The first screen of the game will be also
        -- provided as the observation.
        return self.config.gameOverReward, self:_generateObservations()
    end

    local reward = self.ale:act(actions[1][1])
    return reward, self:_generateObservations()
end

function Env:getRgbFromPalette(obs)
    return alewrap.getRgbFromPalette(obs)
end

function Env:_createObs()
    -- The torch.data() function is provided by torchffi.
    local obs = torch.ByteTensor(HEIGHT, WIDTH)
    self.ale:fillObs(torch.data(obs), obs:nElement())
    return obs
end

function Env:_createRamObs()
    local ram = torch.ByteTensor(RAM_LENGTH)
    self.ale:fillRamObs(torch.data(ram), ram:nElement())
    return ram
end

function Env:_display(obs)
    require 'image'
    local frame = self:getRgbFromPalette(obs)
    self.win = image.display({image=frame, win=self.win})
end

-- Generates the observations for the current step.
function Env:_generateObservations()
    local obs = self:_createObs()
    if self.config.display then
        self:_display(obs)
    end

    if self.config.enableRamObs then
        local ram = self:_createRamObs()
        return {obs, ram}
    else
        return {obs}
    end
end

function Env:saveState()
    self.ale:saveState()
end

function Env:loadState()
    return self.ale:loadState()
end

function Env:actions()
    local nactions = self.ale:numActions()
    local actions = torch.IntTensor(nactions)
    self.ale:actions(torch.data(actions))
    return actions
end

function Env:lives()
    return self.ale:lives()
end
