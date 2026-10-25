-- TM Hotseat — Trackmania-style hotseat mode for Assetto Corsa (CSP Lua app).
-- Entry point: wires the game logic, ghost system and UI to CSP callbacks.

local game = require('src/game')
local ghosts = require('src/ghosts')
local panels = require('src/panels')
local overlay = require('src/overlay')
local controls = require('src/controls')

math.randomseed(os.time and os.time() or 42)

-- Ghosts ask the game which recordings to replay (avoids a require cycle).
ghosts.targetsFn = game.getGhostTargets

-- One bound button: GO on the handover screen, restart while driving.
controls.init(function()
  local phase = game.state.phase
  if phase == game.PHASE_HANDOVER then
    game.confirmHandover()
  elseif phase == game.PHASE_DRIVING then
    game.requestRestart()
  end
end)

-- Pick up a game that survived a session restart or app reload.
game.tryRestore()

function script.update(dt)
  game.update(dt)
  panels.autoHideWindow()
  ghosts.update(dt, game.state.phase == game.PHASE_DRIVING, game.waitingForLine())
end

function script.windowMain(dt)
  panels.drawMain(dt)
end

function script.fullscreenUI(dt)
  overlay.draw()
end

function script.draw3D(dt)
  ghosts.draw3D()
end
