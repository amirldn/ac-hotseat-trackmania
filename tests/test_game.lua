-- Offline smoke test for the TM Hotseat state machine, with CSP APIs stubbed.
package.path = 'apps/lua/tm_hotseat/?.lua;' .. package.path -- run from repo root

-- ---------------------------------------------------------------- CSP stubs
local vecMt
vecMt = {
  __index = {
    set = function(s, x, y, z) s.x, s.y, s.z = x, y, z; return s end,
    clone = function(s) return setmetatable({ x = s.x, y = s.y, z = s.z }, vecMt) end,
  },
  __add = function(a, b) return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, vecMt) end,
}
function vec3(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, vecMt) end
function vec2(x, y) return { x = x, y = y } end
function rgbm(r, g, b, m) return { r, g, b, m } end
stringify = setmetatable({ parse = function(s) return s end }, { __call = function(_, t) return t end })

local car = {
  lapCount = 0, lapTimeMs = 0, previousLapTimeMs = 0, wheelsOutside = 0,
  position = vec3(), look = vec3(0, 0, 1), up = vec3(0, 1, 0),
}
local simState = { isPaused = false, isReplayActive = false, trackLengthM = 4000 }

ac = {
  getCar = function() return car end,
  getSim = function() return simState end,
  storage = function(t) return t end,
  tryToRestartSession = function() end,
  getCarID = function() return 'test_car' end,
  getFolder = function() return '/nonexistent' end,
  FolderID = { ContentCars = 1 },
  INIConfig = { load = function() error('no ini') end },
  findNodes = function() error('no scene') end,
  SpawnSet = { HotlapStart = 1, Start = 2, Pits = 3 },
}
physics = {} -- no teleport -> game falls through to ac.tryToRestartSession
io.fileExists = function() return false end

-- ---------------------------------------------------------------- harness
local game = require('src/game')
local ghosts = require('src/ghosts')
ghosts.targetsFn = game.getGhostTargets

local failures = 0
local function check(cond, label)
  if cond then print('PASS ' .. label) else failures = failures + 1; print('FAIL ' .. label) end
end

local function tick(dt)
  game.update(dt or 0.1)
  ghosts.update(dt or 0.1, game.state.phase == game.PHASE_DRIVING)
end

local function crossStartLine()
  car.lapTimeMs = 50 -- car just crossed the timing line
  tick()
end

local function completeLap(ms, cut)
  -- simulate the lap running
  for i = 1, 5 do
    car.lapTimeMs = ms * i / 5
    if cut then car.wheelsOutside = 4 end
    tick()
    car.wheelsOutside = 0
  end
  car.lapCount = car.lapCount + 1
  car.previousLapTimeMs = ms
  car.lapTimeMs = 20
  tick()
end

-- ---------------------------------------------------------------- scenario
math.randomseed(1234)
game.setup.playerCount = 3
game.setup.fuelSeconds = 100
game.startGame()
check(game.state.phase == game.PHASE_HANDOVER and game.state.current == 1, 'game starts in handover for player 1')
check(#game.state.players == 3 and game.state.players[1].nick ~= game.state.players[2].nick, 'players have unique nicknames')

-- Opening: player 1 sets 60s lap (with an invalid cut lap first).
game.confirmHandover()
check(game.state.phase == game.PHASE_DRIVING, 'driving after GO')
crossStartLine()
completeLap(58000, true) -- cut lap must not count
check(game.state.players[1].best == nil and game.state.phase == game.PHASE_DRIVING, 'cut lap rejected, still driving')
completeLap(60000)
check(game.state.players[1].best == 60000, 'player 1 lap banked')
check(game.state.phase == game.PHASE_HANDOVER and game.state.current == 2, 'handover to player 2')
local fuelAfterP1 = game.state.players[1].fuel
check(fuelAfterP1 < 100 and fuelAfterP1 > 90, 'player 1 fuel drained during turn only')

-- Opening: player 2 sets 50s, player 3 sets 55s.
game.confirmHandover(); crossStartLine(); completeLap(50000)
check(game.state.current == 3, 'handover to player 3')
game.confirmHandover(); crossStartLine(); completeLap(55000)

-- All laps set -> elimination, worst (player 1, 60s) drives.
check(game.state.mode == game.MODE_ELIMINATION, 'elimination mode begins')
check(game.state.current == 1, 'worst player (p1, 60s) is on the wheel')
check(game.playerAbove(1) == 3, 'target is the player directly above (p3, 55s)')
check(game.leaderIndex() == 2, 'leader is p2 (50s)')

-- Ghost targets: leader ghost + player-above ghost exist (recorded laps).
game.confirmHandover(); crossStartLine()
local targets = game.getGhostTargets()
check(#targets == 2, 'two ghosts on track (leader + player above)')

-- P1 improves but stays last -> keeps driving.
completeLap(59000)
check(game.state.phase == game.PHASE_DRIVING and game.state.current == 1, 'still last, keeps driving')

-- P1 beats p3 -> wheel passes to p3 (new last).
completeLap(54000)
check(game.state.phase == game.PHASE_HANDOVER and game.state.current == 3, 'beaten player takes the wheel')

-- P3 runs out of fuel -> last-chance overtime (keeps driving, not eliminated).
game.state.players[3].fuel = 0.05
game.confirmHandover()
tick(0.2)
check(game.state.overtime and game.state.phase == game.PHASE_DRIVING and game.state.current == 3,
  'fuel out gives p3 an overtime last chance')
check(not game.state.players[3].eliminated, 'overtime does not eliminate immediately')
-- Restarting during overtime forfeits it -> p3 eliminated, p1 (worst left) drives.
game.requestRestart()
check(game.state.players[3].eliminated, 'restart during overtime eliminates p3')
check(game.state.phase == game.PHASE_HANDOVER and game.state.current == 1, 'remaining worst (p1) drives next')

-- P1 runs out of fuel, forfeits overtime -> only p2 remains -> game over, p2 wins.
game.state.players[1].fuel = 0.05
game.confirmHandover()
tick(0.2)
check(game.state.overtime, 'p1 enters overtime')
game.requestRestart()
check(game.state.phase == game.PHASE_OVER, 'game over when one player remains')
local winner
for _, p in ipairs(game.state.players) do if not p.eliminated then winner = p end end
check(winner == game.state.players[2], 'winner is the surviving leader')

-- Restart button: fuel keeps draining, lap marked dirty.
game.resetGame()
game.setup.playerCount = 2
game.setup.fuelSeconds = 100
game.startGame(); game.confirmHandover(); crossStartLine()
car.lapTimeMs = 30000
game.requestRestart()
check(game.state.lapDirty, 'restart marks lap dirty')
completeLap(40000)
check(game.state.phase == game.PHASE_DRIVING and game.state.players[game.state.current].best == nil, 'dirty lap ignored')
crossStartLine()
completeLap(45000)
check(game.state.phase == game.PHASE_HANDOVER, 'clean lap after restart counts')

-- Overtime survival: run dry mid-lap, then a valid lap still banks and passes on.
game.resetGame()
game.setup.playerCount = 2
game.setup.fuelSeconds = 100
game.startGame()
local cur = game.state.current
game.confirmHandover(); crossStartLine()
game.state.players[cur].fuel = 0.05
tick(0.2)
check(game.state.overtime and game.state.phase == game.PHASE_DRIVING, 'fuel out enters overtime, still driving')
completeLap(48000)
check(game.state.players[cur].best == 48000, 'valid lap during overtime still banks')
check(game.state.phase == game.PHASE_HANDOVER, 'overtime valid lap passes the wheel')

-- Overtime + external restart (pause-menu "restart session" / wheel button):
-- the lap counter drops, which must forfeit the last chance just like the app's
-- own Restart button does.
game.resetGame()
game.setup.playerCount = 3
game.setup.fuelSeconds = 100
game.startGame()
local cur2 = game.state.current
car.lapCount = 5
game.confirmHandover(); crossStartLine()
game.state.players[cur2].fuel = 0.05
tick(0.2)
check(game.state.overtime, 'overtime reached before external restart')
car.lapCount = 0 -- session restart drops the lap counter
tick()
check(game.state.phase == game.PHASE_HANDOVER and game.state.current ~= cur2,
  'external restart during overtime forfeits to the next player')

print(failures == 0 and '\nALL TESTS PASSED' or ('\n' .. failures .. ' FAILURES'))
os.exit(failures == 0 and 0 or 1)
