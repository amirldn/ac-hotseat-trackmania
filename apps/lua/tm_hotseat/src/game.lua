-- Trackmania-hotseat game logic.
--
-- Flow:
--   SETUP      pick player count, nickname category and fuel budget
--   OPENING    each player in (shuffled) order drives until they set one valid
--              lap; fuel drains the whole time and restarting keeps the drain
--   ELIMINATION the worst-ranked player drives and must beat the player ranked
--              directly above them; succeed and the beaten player (now last)
--              takes the wheel; run out of fuel and you're eliminated
--   OVER       one player left standing — winner
--
-- "Fuel" is a virtual per-player time budget (seconds of driving time), not
-- the car's actual fuel tank. It only drains during that player's own turns
-- and pauses on valid laps / handovers, exactly like Trackmania hotseat.

local ghosts = require('src/ghosts')
local nicknames = require('src/nicknames')
local sound = require('src/sound')

local M = {}

-- Forward declaration: requestRestart (below) needs to trigger a fuel-out when
-- the player restarts during their last-chance overtime, but onFuelOut is
-- defined later alongside the other lap-result handlers.
local onFuelOut

M.PHASE_SETUP, M.PHASE_HANDOVER, M.PHASE_DRIVING, M.PHASE_OVER = 'setup', 'handover', 'driving', 'over'
M.MODE_OPENING, M.MODE_ELIMINATION = 'opening', 'elimination'

M.cfg = {
  maxWheelsOutside = 2,   -- more wheels off track than this invalidates the lap
  cutGraceS = 0.12,       -- ...but only if held longer than this (kerb bounces)
  fuelStepS = 30,         -- +/- step in setup
  minFuelS = 60,
  maxFuelS = 3600,
}

M.setup = {
  playerCount = 3,
  categoryIndex = 1,
  fuelSeconds = nil, -- filled from track length on first UI draw
}

M.state = {
  phase = M.PHASE_SETUP,
  mode = M.MODE_OPENING,
  players = {},      -- { nick, fuel, fuelMax, best (ms|nil), bestStamp, eliminated }
  current = nil,     -- players index of the active driver
  stampCounter = 0,  -- monotonic counter for tie-breaking equal lap times
  message = nil,     -- transient status line shown in the driving panel
  -- per-attempt lap tracking
  lapBase = nil,
  lapInvalid = false,
  lapDirty = false,  -- teleported/restarted mid-lap: next completed lap doesn't count
  cutTimer = 0,
  lastLapTimeMs = nil,  -- previous frame's running lap timer, to spot external restarts
  overtime = false,     -- fuel ran out mid-turn: last-chance lap, restart to forfeit
}

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------

local function sim() return ac.getSim() end

function M.trackLengthKm()
  local km = 4
  pcall(function()
    local m = sim().trackLengthM
    if m and m > 100 then km = m / 1000 end
  end)
  return km
end

function M.defaultFuelSeconds()
  local s = 120 + 75 * M.trackLengthKm()
  return math.min(M.cfg.maxFuelS, math.max(M.cfg.minFuelS, math.floor(s / 30 + 0.5) * 30))
end

---Active (non-eliminated) players sorted best lap first; nil laps rank last,
---equal laps rank the earlier setter higher (you must strictly beat a time).
function M.ranking()
  local list = {}
  for i, p in ipairs(M.state.players) do
    if not p.eliminated then list[#list + 1] = { index = i, p = p } end
  end
  table.sort(list, function(a, b)
    if a.p.best and b.p.best then
      if a.p.best ~= b.p.best then return a.p.best < b.p.best end
      return a.p.bestStamp < b.p.bestStamp
    end
    if a.p.best then return true end
    if b.p.best then return false end
    return a.index < b.index
  end)
  return list
end

function M.countActive()
  local n = 0
  for _, p in ipairs(M.state.players) do
    if not p.eliminated then n = n + 1 end
  end
  return n
end

local function worstActiveIndex()
  local r = M.ranking()
  return #r > 0 and r[#r].index or nil
end

---The player ranked directly above `playerIndex`, or nil if they lead.
function M.playerAbove(playerIndex)
  local r = M.ranking()
  for pos, e in ipairs(r) do
    if e.index == playerIndex then
      return pos > 1 and r[pos - 1].index or nil
    end
  end
  return nil
end

function M.leaderIndex()
  local r = M.ranking()
  return #r > 0 and r[1].p.best and r[1].index or nil
end

---Ghost targets for the active driver: overall leader + the player directly
---above them (when those differ and have recordings).
function M.getGhostTargets()
  local s = M.state
  if s.phase ~= M.PHASE_DRIVING or s.current == nil then return {} end
  local out, used = {}, {}
  local function add(idx, label, color)
    if idx and not used[idx] and ghosts.recordings[idx] then
      used[idx] = true
      out[#out + 1] = { rec = ghosts.recordings[idx], label = label .. ' ' .. s.players[idx].nick, color = color }
    end
  end
  add(M.leaderIndex(), '👑', rgbm(1, 0.85, 0.2, 1))
  add(M.playerAbove(s.current), '▲', rgbm(0.4, 0.8, 1, 1))
  return out
end

-- ----------------------------------------------------------------------------
-- Persistence (survives session restarts and app reloads; ghosts don't)
-- ----------------------------------------------------------------------------

local store = ac.storage({ saved = '' }, 'tm_hotseat')

function M.save()
  local s = M.state
  local ok, data = pcall(stringify, {
    phase = s.phase, mode = s.mode, current = s.current, stampCounter = s.stampCounter,
    players = s.players, fuelSeconds = M.setup.fuelSeconds,
  })
  if ok then store.saved = data end
end

function M.tryRestore()
  if store.saved == nil or store.saved == '' then return end
  local ok, data = pcall(stringify.parse, store.saved)
  if not ok or type(data) ~= 'table' or type(data.players) ~= 'table' or #data.players == 0 then return end
  local s = M.state
  s.players, s.mode, s.current = data.players, data.mode or M.MODE_OPENING, data.current
  s.stampCounter = data.stampCounter or 0
  M.setup.fuelSeconds = data.fuelSeconds
  if data.phase == M.PHASE_OVER then
    s.phase = M.PHASE_OVER
  elseif data.phase == M.PHASE_DRIVING or data.phase == M.PHASE_HANDOVER then
    -- Never restore straight into a running turn — re-confirm the handover.
    s.phase = s.current and M.PHASE_HANDOVER or M.PHASE_SETUP
  end
end

function M.resetGame()
  M.state.phase = M.PHASE_SETUP
  M.state.players = {}
  M.state.current = nil
  M.state.message = nil
  ghosts.clearAll()
  store.saved = ''
end

-- ----------------------------------------------------------------------------
-- Phase transitions
-- ----------------------------------------------------------------------------

function M.startGame()
  local s = M.state
  local count = M.setup.playerCount
  local nicks = nicknames.pick(M.setup.categoryIndex, count)
  local fuel = M.setup.fuelSeconds or M.defaultFuelSeconds()
  s.players = {}
  for i = 1, count do
    s.players[i] = { nick = nicks[i], fuel = fuel, fuelMax = fuel, best = nil, bestStamp = 0, eliminated = false }
  end
  -- Shuffle the driving order for fairness.
  for i = count, 2, -1 do
    local j = math.random(i)
    s.players[i], s.players[j] = s.players[j], s.players[i]
  end
  s.mode = M.MODE_OPENING
  s.stampCounter = 0
  s.message = nil
  ghosts.clearAll()
  M.beginHandover(1)
end

function M.beginHandover(playerIndex)
  local s = M.state
  s.phase = M.PHASE_HANDOVER
  s.current = playerIndex
  s.overtime = false
  ghosts.abortRecording()
  sound.next()
  M.save()
end

---Called from the handover screen's GO button: puts the car at the hotlap
---start and hands control to the current player.
function M.confirmHandover()
  local s = M.state
  s.phase = M.PHASE_DRIVING
  s.message = nil
  M.teleportToStart()
  -- The out-lap section up to the timing line never counts; recording starts
  -- once the line is crossed.
  s.lapBase = nil
  s.lapInvalid = false
  s.lapDirty = true
  s.cutTimer = 0
  s.lastLapTimeMs = nil
  s.overtime = false
  ghosts.abortRecording()
  M.save()
end

---Discard any in-progress lap and start fresh from the line: clear the cut
---flag, re-arm the clean-lap gate and drop the current ghost recording. Used by
---the Restart button and whenever an external restart is detected mid-turn.
function M.armCleanLap()
  M.state.lapInvalid = false
  M.state.lapDirty = true
  M.state.cutTimer = 0
  ghosts.abortRecording()
end

---Restart button: back to the hotlap start, fuel keeps its level (and keeps
---draining) — exactly like Trackmania. Restarting during overtime (fuel already
---gone) means giving up the last-chance lap, so the wheel passes on instead.
function M.requestRestart()
  if M.state.phase ~= M.PHASE_DRIVING then return end
  if M.state.overtime then
    onFuelOut()
    return
  end
  M.teleportToStart()
  M.armCleanLap()
end

---Best-effort teleport chain; not every CSP build/session allows every method.
function M.teleportToStart()
  local attempts = {
    function() physics.teleportCarTo(0, ac.SpawnSet.HotlapStart) end,
    function() physics.teleportCarTo(0, ac.SpawnSet.Start) end,
    function() physics.teleportCarTo(0, ac.SpawnSet.Pits) end,
    -- Last resort: restart the whole session. Our state lives in this app
    -- (and in ac.storage), so nothing is lost except ghost recordings' AC-side
    -- lap history, which we don't use anyway.
    function() ac.tryToRestartSession() end,
  }
  for _, fn in ipairs(attempts) do
    if pcall(fn) then return true end
  end
  M.state.message = 'Teleport unavailable — drive back to the line'
  return false
end

-- ----------------------------------------------------------------------------
-- Lap results
-- ----------------------------------------------------------------------------

local function nextOpeningDriver(afterIndex)
  local players = M.state.players
  for step = 1, #players do
    local i = (afterIndex + step - 1) % #players + 1
    local p = players[i]
    if not p.eliminated and p.best == nil then return i end
  end
  return nil
end

local function finishGameIfDecided()
  local s = M.state
  local active = M.countActive()
  if active <= 1 then
    s.phase = M.PHASE_OVER
    s.current = nil
    M.save()
    return true
  end
  return false
end

local function onValidLap(lapMs)
  local s = M.state
  local p = s.players[s.current]
  if p == nil then return end

  local improved = p.best == nil or lapMs < p.best
  if improved then
    p.best = lapMs
    s.stampCounter = s.stampCounter + 1
    p.bestStamp = s.stampCounter
    ghosts.commitLap(s.current, lapMs)
  else
    ghosts.abortRecording()
  end

  if s.mode == M.MODE_OPENING then
    -- One valid lap ends the opening turn; fuel drain pauses here.
    local nxt = nextOpeningDriver(s.current)
    if nxt ~= nil then
      M.beginHandover(nxt)
    else
      s.mode = M.MODE_ELIMINATION
      if not finishGameIfDecided() then M.beginHandover(worstActiveIndex()) end
    end
  else
    -- Elimination: only a lap that lifts you off last place passes the wheel.
    local worst = worstActiveIndex()
    if worst ~= s.current then
      s.message = nil
      M.beginHandover(worst)
    else
      s.message = improved and 'Improved — but still last. Keep pushing!' or 'Not enough. Keep pushing!'
      M.save()
    end
  end
end

-- Assigned to the local forward-declared near the top of the file.
function onFuelOut()
  local s = M.state
  local p = s.players[s.current]
  p.eliminated = true
  p.fuel = 0
  s.overtime = false
  ghosts.abortRecording()
  if finishGameIfDecided() then return end
  if s.mode == M.MODE_OPENING then
    local nxt = nextOpeningDriver(s.current)
    if nxt ~= nil then
      M.beginHandover(nxt)
      return
    end
    s.mode = M.MODE_ELIMINATION
    if finishGameIfDecided() then return end
  end
  M.beginHandover(worstActiveIndex())
end

-- ----------------------------------------------------------------------------
-- Per-frame update
-- ----------------------------------------------------------------------------

function M.update(dt)
  local s = M.state
  if s.phase ~= M.PHASE_DRIVING or s.current == nil then return end
  local car = ac.getCar(0)
  if car == nil then return end

  local paused = false
  pcall(function()
    local sm = sim()
    paused = sm.isPaused or sm.isReplayActive
  end)

  -- Fuel drains for the whole turn, restarts included. Running dry doesn't end
  -- the turn immediately: the driver gets a last-chance "overtime" to finish the
  -- lap they're on. They only pass the wheel by setting a valid lap (survive) or
  -- restarting (forfeit — handled in requestRestart).
  if not paused and not s.overtime then
    local p = s.players[s.current]
    p.fuel = p.fuel - dt
    if p.fuel <= 0 then
      p.fuel = 0
      s.overtime = true
    end
  end

  -- Detect a restart the app didn't trigger itself: a pause-menu "restart
  -- session", a wheel button, or any external teleport back to the line. These
  -- either drop the lap counter (session restart) or reset the running lap
  -- timer without completing a lap. Re-arm a clean lap so a cut that was flagged
  -- *before* the restart can't void the fresh lap that follows.
  local lapTimeMs = car.lapTimeMs or 0
  if s.lapBase ~= nil then
    local droppedLap = car.lapCount < s.lapBase
    local timerReset = s.lastLapTimeMs ~= nil and s.lastLapTimeMs > 3000
      and lapTimeMs < 1500 and car.lapCount <= s.lapBase
    if droppedLap or timerReset then
      if s.overtime then
        -- Restarting while out of fuel (by any method) forfeits the last chance.
        onFuelOut()
        return
      end
      s.lapBase = car.lapCount
      M.armCleanLap()
    end
  end
  s.lastLapTimeMs = lapTimeMs

  -- Track-cut detection: too many wheels off track for too long voids the lap.
  local wheelsOut = car.wheelsOutside or 0
  if wheelsOut > M.cfg.maxWheelsOutside then
    s.cutTimer = s.cutTimer + dt
    if s.cutTimer > M.cfg.cutGraceS and not s.lapInvalid then
      s.lapInvalid = true
      sound.invalid()  -- ding once, on the transition to invalid
    end
  else
    s.cutTimer = 0
  end

  -- Lap completion. lapCount can also go DOWN (session-restart fallback of
  -- the teleport chain) — re-anchor instead of waiting for it to catch up.
  if s.lapBase == nil or car.lapCount < s.lapBase then s.lapBase = car.lapCount end
  if car.lapCount > s.lapBase then
    local lapMs = car.previousLapTimeMs
    local counts = not s.lapInvalid and not s.lapDirty and lapMs ~= nil and lapMs > 0
    s.lapBase = car.lapCount
    s.lapInvalid = false
    s.lapDirty = false
    s.cutTimer = 0
    if counts then
      -- onValidLap consumes the finished lap's buffer via ghosts.commitLap.
      onValidLap(lapMs)
    end
    ghosts.onLineCross()
  end

  -- First crossing of the line after a handover/restart arms a clean lap.
  if s.lapDirty and car.lapTimeMs ~= nil and car.lapTimeMs >= 0 and car.lapTimeMs < 500 then
    s.lapDirty = false
    s.lapInvalid = false
    s.cutTimer = 0
    ghosts.onLineCross()
  end
end

return M
