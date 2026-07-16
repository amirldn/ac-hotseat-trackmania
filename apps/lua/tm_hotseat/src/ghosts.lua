-- Ghost recording and playback.
--
-- While a player drives, car position/orientation is sampled at a fixed rate.
-- When they complete a valid lap that improves their personal best, the
-- recording is stored for that player. During later attempts up to two ghosts
-- replay in real time against the current lap clock:
--   1. the overall leader's best lap
--   2. the best lap of the player ranked directly above the current driver
--
-- Ghosts are rendered by loading the player's car KN5 into extra scene nodes
-- (no collisions, purely visual). If the model can't be loaded, a debug marker
-- is drawn in the 3D scene instead.

local M = {}

local SAMPLE_INTERVAL = 1 / 20   -- seconds between samples
local MAX_SAMPLES = 20 * 60 * 20 -- cap: 20 minutes of lap time per recording

-- Wired up by tm_hotseat.lua to avoid a require cycle with game.lua.
-- Must return an array of { rec = recording, label = string, color = rgbm }.
M.targetsFn = function() return {} end

M.recordings = {} -- playerIndex -> { lapMs = number, samples = flat number array, count = int }

local recording = nil -- active buffer: { samples = {}, count = 0, clock = 0 }

-- ----------------------------------------------------------------------------
-- Recording
-- ----------------------------------------------------------------------------

---Starts a fresh recording buffer; call when the car crosses the timing line.
function M.onLineCross()
  recording = { samples = {}, count = 0, clock = 0 }
end

---Drops the active buffer; call on teleports/handovers so partial laps never commit.
function M.abortRecording()
  recording = nil
end

---Stores the just-finished buffer as `playerIndex`'s best-lap ghost.
---@param playerIndex integer
---@param lapMs number
function M.commitLap(playerIndex, lapMs)
  if recording and recording.count >= 2 then
    M.recordings[playerIndex] = {
      lapMs = lapMs,
      samples = recording.samples,
      count = recording.count,
    }
  end
  recording = nil
end

function M.clearAll()
  M.recordings = {}
  recording = nil
end

local function appendSample(car)
  local r = recording
  if r.count >= MAX_SAMPLES then return end
  local s, base = r.samples, r.count * 10
  s[base + 1] = car.lapTimeMs
  s[base + 2] = car.position.x
  s[base + 3] = car.position.y
  s[base + 4] = car.position.z
  s[base + 5] = car.look.x
  s[base + 6] = car.look.y
  s[base + 7] = car.look.z
  s[base + 8] = car.up.x
  s[base + 9] = car.up.y
  s[base + 10] = car.up.z
  r.count = r.count + 1
end

-- ----------------------------------------------------------------------------
-- Ghost scene nodes
-- ----------------------------------------------------------------------------

local slots = {}          -- up to 2 reusable ghost nodes: { node, loaded, failed }
local modelPath = nil
local modelPathResolved = false

local function resolveCarModelPath()
  if modelPathResolved then return modelPath end
  modelPathResolved = true
  pcall(function()
    local carId = ac.getCarID(0)
    local carDir = ac.getFolder(ac.FolderID.ContentCars) .. '/' .. carId
    local candidates = {}
    local ok, ini = pcall(ac.INIConfig.load, carDir .. '/lods.ini')
    if ok and ini then
      -- Prefer a mid LOD: cheaper than LOD_0, still recognisable up close.
      for _, section in ipairs({ 'LOD_1', 'LOD_0', 'LOD_2' }) do
        local file = ini:get(section, 'FILE', '')
        if file ~= '' then candidates[#candidates + 1] = carDir .. '/' .. file end
      end
    end
    candidates[#candidates + 1] = carDir .. '/' .. carId .. '.kn5'
    for _, path in ipairs(candidates) do
      if io.fileExists(path) then
        modelPath = path
        return
      end
    end
  end)
  return modelPath
end

local function ensureSlot(i)
  local slot = slots[i]
  if slot then return slot end
  slot = { node = nil, loaded = false, failed = false }
  slots[i] = slot
  local ok = pcall(function()
    local root = ac.findNodes('trackRoot:yes')
    slot.node = root:createNode('tm_hotseat_ghost_' .. i, true)
    local path = resolveCarModelPath()
    if path == nil then error('car model not found') end
    slot.node:loadKN5Async(path, function(err, loaded)
      if err or loaded == nil then
        slot.failed = true
        return
      end
      slot.loaded = true
      -- Best effort ghost look; harmless if unsupported on this CSP build.
      pcall(function() loaded:setTransparent(true) end)
    end)
  end)
  if not ok then slot.failed = true end
  return slot
end

local function hideSlot(i)
  local slot = slots[i]
  if slot and slot.node then
    pcall(function() slot.node:setVisible(false) end)
  end
  if slot then slot.active = nil end
end

-- Binary search for the sample pair bracketing time `t`, then interpolate.
local tmpPos, tmpLook, tmpUp = vec3(), vec3(), vec3()
local function sampleAt(rec, t)
  local s, n = rec.samples, rec.count
  if n < 2 or t < s[1] then return nil end
  if t > s[(n - 1) * 10 + 1] then return nil end
  local lo, hi = 0, n - 1
  while hi - lo > 1 do
    local mid = math.floor((lo + hi) / 2)
    if s[mid * 10 + 1] <= t then lo = mid else hi = mid end
  end
  local a, b = lo * 10, hi * 10
  local ta, tb = s[a + 1], s[b + 1]
  local f = tb > ta and (t - ta) / (tb - ta) or 0
  tmpPos:set(s[a + 2] + (s[b + 2] - s[a + 2]) * f, s[a + 3] + (s[b + 3] - s[a + 3]) * f, s[a + 4] + (s[b + 4] - s[a + 4]) * f)
  tmpLook:set(s[a + 5] + (s[b + 5] - s[a + 5]) * f, s[a + 6] + (s[b + 6] - s[a + 6]) * f, s[a + 7] + (s[b + 7] - s[a + 7]) * f)
  tmpUp:set(s[a + 8] + (s[b + 8] - s[a + 8]) * f, s[a + 9] + (s[b + 9] - s[a + 9]) * f, s[a + 10] + (s[b + 10] - s[a + 10]) * f)
  return tmpPos, tmpLook, tmpUp
end

-- Markers drawn by script.draw3D when a slot has no loaded car model.
local fallbackMarkers = {}

-- ----------------------------------------------------------------------------
-- Per-frame update
-- ----------------------------------------------------------------------------

---@param dt number
---@param drivingActive boolean @True while a player's turn is running.
function M.update(dt, drivingActive)
  local car = ac.getCar(0)
  fallbackMarkers = {}
  if car == nil then return end

  -- Record.
  if drivingActive and recording ~= nil then
    recording.clock = recording.clock + dt
    if recording.clock >= SAMPLE_INTERVAL then
      recording.clock = recording.clock - SAMPLE_INTERVAL
      if car.lapTimeMs ~= nil and car.lapTimeMs > 0 then appendSample(car) end
    end
  end

  -- Play back.
  local targets = drivingActive and M.targetsFn() or {}
  for i = 1, 2 do
    local target = targets[i]
    local shown = false
    if target and target.rec then
      local pos, look, up = sampleAt(target.rec, car.lapTimeMs or 0)
      if pos ~= nil then
        local slot = ensureSlot(i)
        if slot.loaded and slot.node then
          local ok = pcall(function()
            slot.node:setPosition(pos)
            slot.node:setOrientation(look, up)
            slot.node:setVisible(true)
          end)
          shown = ok
          slot.active = shown and { pos = pos:clone(), label = target.label, color = target.color } or nil
        end
        if not shown then
          fallbackMarkers[#fallbackMarkers + 1] = { pos = pos:clone(), label = target.label, color = target.color }
        end
      end
    end
    if not shown then hideSlot(i) end
  end
end

---Draws name tags over ghosts and marker crosses when no car model is available.
---Called from script.draw3D (TRANSPARENT render callback); everything is
---best-effort since debug-draw helpers vary between CSP builds.
function M.draw3D()
  for i = 1, 2 do
    local slot = slots[i]
    if slot and slot.active then
      pcall(function() render.debugText(slot.active.pos + vec3(0, 1.6, 0), slot.active.label) end)
    end
  end
  for _, m in ipairs(fallbackMarkers) do
    pcall(function()
      render.debugCross(m.pos, 2, m.color or rgbm(1, 1, 1, 1))
      render.debugText(m.pos + vec3(0, 1.6, 0), m.label)
    end)
  end
end

return M
