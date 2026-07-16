-- TM Hotseat — Trackmania-style hotseat mode for Assetto Corsa (CSP Lua app).
-- Entry point: wires the game logic, ghost system and UI to CSP callbacks.

local game = require('src/game')
local ghosts = require('src/ghosts')
local panels = require('src/panels')

math.randomseed(os.time and os.time() or 42)

-- Ghosts ask the game which recordings to replay (avoids a require cycle).
ghosts.targetsFn = game.getGhostTargets

-- Pick up a game that survived a session restart or app reload.
game.tryRestore()

function script.update(dt)
  game.update(dt)
  ghosts.update(dt, game.state.phase == game.PHASE_DRIVING)
end

function script.windowMain(dt)
  panels.drawMain(dt)
end

function script.draw3D(dt)
  ghosts.draw3D()
end
