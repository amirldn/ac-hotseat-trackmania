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
  minLapFraction = 0.6,   -- a lap must cover this share of the track length (rejects out-laps)
  teleportCheckFrames = 12, -- frames to wait before deciding a teleport method did nothing
  teleportMinJumpM = 15,  -- the car must move at least this far for a teleport to count
  saveIntervalS = 5,      -- persist fuel this often mid-turn, so a crash doesn't refund it
  splitShowS = 3.5,       -- how long a checkpoint split stays on screen
}

-- Monotonic clock (seconds) for UI timers like split chips; advanced in update().
M.clock = 0

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
  lapDist = 0,          -- metres driven since the lap was armed (teleport jumps excluded)
  lastPos = nil,        -- previous frame's car position { x, y, z } for lapDist
  teleport = nil,       -- pending teleport being verified: { step, frames, x, y, z, slow }
  saveTimer = 0,
  -- Trackmania-style checkpoints: the lap is split into cpCount equal spline
  -- sectors; crossing each one flashes your split against the target's ghost.
  cpCount = 0,
  cpNext = 1,
  split = nil,          -- { cp, n, time, delta|nil, final, at } for the HUD chip
  lastLap = nil,        -- { nick, time, delta|nil, vsNick|nil } shown on the handover card
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

---Whose time the active driver is chasing: in elimination the player directly
---above them (beat them or you're out), in the opening round the leader.
function M.splitTargetIndex()
  local s = M.state
  if s.current == nil then return nil end
  if s.mode == M.MODE_ELIMINATION then return M.playerAbove(s.current) end
  local leader = M.leaderIndex()
  return leader ~= s.current and leader or nil
end

function M.checkpointCount()
  return math.max(3, math.min(10, math.floor(M.trackLengthKm() / 0.8 + 0.5)))
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
  s.outCounter = 0
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
  s.lapDist = 0
  s.lastPos = nil
  s.cpCount = M.checkpointCount()
  s.cpNext = 1
  s.split = nil
  s.saveTimer = 0
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
  M.state.lapDist = 0
  M.state.cpNext = 1
  M.state.split = nil
  M.state.message = nil
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
  M.armCleanLap()
  M.teleportToStart()
end

-- Best-effort teleport chain; not every CSP build/session allows every method.
-- A call that doesn't throw isn't proof it worked (some builds silently ignore
-- teleports from apps), so each attempt is verified a few frames later by
-- checking the car actually jumped — if not, the next method is tried.
local TELEPORTS = {
  function() physics.teleportCarTo(0, ac.SpawnSet.HotlapStart) end,
  function() physics.teleportCarTo(0, ac.SpawnSet.Start) end,
  function() physics.teleportCarTo(0, ac.SpawnSet.Pits) end,
  function() ac.tryToTeleportToPits() end,
  -- Last resort: restart the whole session. Our state lives in this app (and
  -- in ac.storage), so nothing is lost. Always trusted: the session reload is
  -- picked up by the lap-counter drop in update().
  function() ac.tryToRestartSession() end,
}

local function tryTeleportFrom(step)
  local s = M.state
  for i = step, #TELEPORTS do
    -- Snapshot before the call: some methods move the car immediately.
    local car = ac.getCar(0)
    local p = car and car.position
    local before = {
      step = i, frames = 0,
      x = p and p.x or 0, y = p and p.y or 0, z = p and p.z or 0,
      slow = car ~= nil and (car.speedKmh or 0) < 3,
    }
    if pcall(TELEPORTS[i]) then
      s.teleport = i < #TELEPORTS and before or nil
      return true
    end
  end
  s.teleport = nil
  s.message = 'Teleport unavailable — drive back to the line'
  return false
end

function M.teleportToStart()
  return tryTeleportFrom(1)
end

---Called every unpaused frame while a teleport is pending.
local function verifyTeleport(car)
  local t = M.state.teleport
  t.frames = t.frames + 1
  local p = car.position
  local dx, dy, dz = p.x - t.x, p.y - t.y, p.z - t.z
  if dx * dx + dy * dy + dz * dz > M.cfg.teleportMinJumpM ^ 2 then
    M.state.teleport = nil -- it worked
  elseif t.frames >= M.cfg.teleportCheckFrames then
    if t.slow and (car.speedKmh or 0) < 3 then
      M.state.teleport = nil -- was already parked at the spawn point
    else
      tryTeleportFrom(t.step + 1)
    end
  end
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

  -- Finish split vs the time being chased (captured before rankings change).
  local targetIdx = M.splitTargetIndex()
  local target = targetIdx and s.players[targetIdx] or nil
  local delta = target and target.best and (lapMs - target.best) or nil
  s.lastLap = { nick = p.nick, time = lapMs, delta = delta, vsNick = target and target.nick or nil }
  s.split = { final = true, n = s.cpCount, time = lapMs, delta = delta, at = M.clock }

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
  -- Elimination order decides final places (last one out finishes 2nd).
  s.outCounter = (s.outCounter or 0) + 1
  p.outOrder = s.outCounter
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

---Accumulates distance driven this lap. Frame-to-frame jumps far beyond what
---the car's speed allows are teleports/resets and don't count.
local function trackDistance(car, dt)
  local s, p = M.state, car.position
  if p == nil then return end
  local last = s.lastPos
  if last ~= nil then
    local dx, dy, dz = p.x - last.x, p.y - last.y, p.z - last.z
    local step = math.sqrt(dx * dx + dy * dy + dz * dz)
    local maxStep = math.max(30, (car.speedKmh or 0) / 3.6 * dt * 3 + 5)
    if step <= maxStep then s.lapDist = s.lapDist + step end
    last.x, last.y, last.z = p.x, p.y, p.z
  else
    s.lastPos = { x = p.x, y = p.y, z = p.z }
  end
end

---Flashes a split when the car crosses the next checkpoint (equal spline
---sectors). Only on a clean lap; the target's time comes from their ghost.
local function trackCheckpoints(car)
  local s = M.state
  local n = s.cpCount
  if s.lapDirty or n < 2 or s.cpNext >= n then return end
  local progress = car.splinePosition
  if progress == nil then return end
  local edge = s.cpNext / n
  -- Upper bound guards the wrap near the line (spline reads ~0.99 right before it).
  if progress >= edge and progress < edge + 0.25 then
    local delta = nil
    local targetIdx = M.splitTargetIndex()
    local rec = targetIdx and ghosts.recordings[targetIdx]
    local targetMs = rec and ghosts.checkpointTime(rec, edge)
    if targetMs then delta = car.lapTimeMs - targetMs end
    s.split = { cp = s.cpNext, n = n, time = car.lapTimeMs, delta = delta, at = M.clock }
    s.cpNext = s.cpNext + 1
  end
end

function M.update(dt)
  M.clock = M.clock + dt
  local s = M.state
  if s.phase ~= M.PHASE_DRIVING or s.current == nil then return end
  local car = ac.getCar(0)
  if car == nil then return end

  local paused = false
  pcall(function()
    local sm = sim()
    paused = sm.isPaused or sm.isReplayActive
  end)

  if not paused and s.teleport ~= nil then verifyTeleport(car) end
  if not paused then trackDistance(car, dt) end

  -- Persist fuel now and then so an AC crash/app reload can't refund a turn.
  s.saveTimer = s.saveTimer + dt
  if s.saveTimer >= M.cfg.saveIntervalS then
    s.saveTimer = 0
    M.save()
  end

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

  trackCheckpoints(car)

  -- Lap completion. lapCount can also go DOWN (session-restart fallback of
  -- the teleport chain) — re-anchor instead of waiting for it to catch up.
  if s.lapBase == nil or car.lapCount < s.lapBase then s.lapBase = car.lapCount end
  if car.lapCount > s.lapBase then
    local lapMs = car.previousLapTimeMs
    local counts = not s.lapInvalid and not s.lapDirty and lapMs ~= nil and lapMs > 0
    -- Distance guard: if AC reset the lap timer on a teleport, the gate below
    -- arms at the spawn point rather than the line, and the short run up to
    -- the line would otherwise bank as a "lap".
    local trackM = M.trackLengthKm() * 1000
    if counts and s.lapDist < trackM * M.cfg.minLapFraction then
      counts = false
      s.message = 'Out-lap ignored — the next lap is the flying lap'
    end
    s.lapBase = car.lapCount
    s.lapInvalid = false
    s.lapDirty = false
    s.cutTimer = 0
    s.lapDist = 0
    s.cpNext = 1
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
    s.lapDist = 0
    s.cpNext = 1
    ghosts.onLineCross()
  end
end

---True while the active driver is between a restart and the timing line
---(lap clock not yet meaningful; ghosts wait at the line).
function M.waitingForLine()
  return M.state.phase == M.PHASE_DRIVING and M.state.lapDirty
end

return M
