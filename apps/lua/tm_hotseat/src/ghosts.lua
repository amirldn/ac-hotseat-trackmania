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
local STRIDE = 11                -- numbers per sample: time, pos xyz, look xyz, up xyz, spline progress
local HIDE_NEAR_M = 6            -- ghost car hides while this close to the driver's car (name stays)

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
  local s, base = r.samples, r.count * STRIDE
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
  s[base + 11] = car.splinePosition or -1
  r.count = r.count + 1
end

-- ----------------------------------------------------------------------------
-- Ghost scene nodes
-- ----------------------------------------------------------------------------

local slots = {}          -- up to 2 reusable ghost nodes: { node, loaded, failed }
local model = nil
local modelResolved = false

---Candidate models for the player's car, best first, as { file, main }: LOD
---KN5s carry no textures, so `main` names the LOD_0 file they borrow them from.
---Car folders don't always match their KN5 names (nohesi_bmw_e90 ships
---bmw_m3_e92_cs.kn5), and lods.ini is usually packed in data.acd, so read it
---through carData and fall back to whatever KN5 files the folder holds.
function M.modelCandidates(carDir, carId)
  local candidates = {}
  local function addLods(ini)
    if ini == nil then return end
    local main = ini:get('LOD_0', 'FILE', '')
    if main == '' then return end
    main = carDir .. '/' .. main
    -- Prefer a mid LOD: cheaper than LOD_0, still recognisable up close.
    local lod1 = ini:get('LOD_1', 'FILE', '')
    if lod1 ~= '' then candidates[#candidates + 1] = { file = carDir .. '/' .. lod1, main = main } end
    candidates[#candidates + 1] = { file = main }
  end
  local ok, ini = pcall(ac.INIConfig.carData, 0, 'lods.ini')
  if ok then pcall(addLods, ini) end
  ok, ini = pcall(ac.INIConfig.load, carDir .. '/lods.ini')
  if ok then pcall(addLods, ini) end
  candidates[#candidates + 1] = { file = carDir .. '/' .. carId .. '.kn5' }
  local listed, files = pcall(io.scanDir, carDir, '*.kn5')
  if listed and type(files) == 'table' then
    -- Main model (shortest name; LODs and the collision mesh can't be shown alone).
    table.sort(files, function(a, b) return #a < #b end)
    for _, f in ipairs(files) do
      local lower = f:lower()
      if not lower:find('collider', 1, true) and not lower:find('_lod', 1, true) then
        candidates[#candidates + 1] = { file = carDir .. '/' .. f }
        break
      end
    end
  end
  return candidates
end

local function resolveCarModel()
  if modelResolved then return model end
  modelResolved = true
  pcall(function()
    local carId = ac.getCarID(0)
    local carDir = ac.getFolder(ac.FolderID.ContentCars) .. '/' .. carId
    for _, c in ipairs(M.modelCandidates(carDir, carId)) do
      if io.fileExists(c.file) and (c.main == nil or io.fileExists(c.main)) then
        model = c
        return
      end
    end
  end)
  return model
end

local function ensureSlot(i)
  local slot = slots[i]
  if slot then return slot end
  slot = { node = nil, loaded = false, failed = false }
  slots[i] = slot
  local ok = pcall(function()
    local root = ac.findNodes('trackRoot:yes')
    slot.node = root:createNode('tm_hotseat_ghost_' .. i, true)
    local m = resolveCarModel()
    if m == nil then error('car model not found') end
    local function onLoaded(err, loaded)
      if err or loaded == nil then
        slot.failed = true
        return
      end
      slot.loaded = true
      -- Material calls only reach meshes, not the node returned by the load
      -- (CSP's traffic tool does the same: findMeshes, then recolour).
      pcall(function() slot.meshes = loaded:findMeshes('?') end)
      local meshes = slot.meshes or loaded
      -- Own materials, so tinting one ghost doesn't repaint the other.
      pcall(function() meshes:ensureUniqueMaterials() end)
      -- Best effort ghost look; harmless if unsupported on this CSP build.
      pcall(function() meshes:setTransparent(true) end)
    end
    if m.main then
      slot.node:loadKN5LODAsync(m.file, m.main, onLoaded)
    else
      slot.node:loadKN5Async(m.file, onLoaded)
    end
  end)
  if not ok then slot.failed = true end
  return slot
end

---Paints the ghost one flat colour. A loose KN5 doesn't get the car's CSP
---config (paint, PBR shader swaps), so real paint comes out pink/orange on mod
---cars; a solid player colour reads as a Trackmania ghost on any car.
local function tintSlot(slot, color)
  if slot.meshes == nil or color == nil or slot.tint == color then return end
  slot.tint = color
  pcall(function() slot.meshes:setMaterialTexture('txDiffuse', color) end)
  pcall(function() slot.meshes:setMaterialTexture('txDetail', rgbm(1, 1, 1, 1)) end)
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
  if t > s[(n - 1) * STRIDE + 1] then return nil end
  local lo, hi = 0, n - 1
  while hi - lo > 1 do
    local mid = math.floor((lo + hi) / 2)
    if s[mid * STRIDE + 1] <= t then lo = mid else hi = mid end
  end
  local a, b = lo * STRIDE, hi * STRIDE
  local ta, tb = s[a + 1], s[b + 1]
  local f = tb > ta and (t - ta) / (tb - ta) or 0
  tmpPos:set(s[a + 2] + (s[b + 2] - s[a + 2]) * f, s[a + 3] + (s[b + 3] - s[a + 3]) * f, s[a + 4] + (s[b + 4] - s[a + 4]) * f)
  tmpLook:set(s[a + 5] + (s[b + 5] - s[a + 5]) * f, s[a + 6] + (s[b + 6] - s[a + 6]) * f, s[a + 7] + (s[b + 7] - s[a + 7]) * f)
  tmpUp:set(s[a + 8] + (s[b + 8] - s[a + 8]) * f, s[a + 9] + (s[b + 9] - s[a + 9]) * f, s[a + 10] + (s[b + 10] - s[a + 10]) * f)
  return tmpPos, tmpLook, tmpUp
end

---Lap time (ms) at which `rec` first reached spline progress `fraction`,
---interpolated between samples; nil if the recording never got there (or was
---made on a build without spline data). Cached per recording.
function M.checkpointTime(rec, fraction)
  rec.cpCache = rec.cpCache or {}
  local cached = rec.cpCache[fraction]
  if cached ~= nil then return cached or nil end
  local s, result = rec.samples, false
  local prevT, prevP = nil, nil
  for i = 0, rec.count - 1 do
    local t, p = s[i * STRIDE + 1], s[i * STRIDE + 11]
    -- Same wrap guard as the live check: ignore readings just before the line.
    if p ~= nil and p >= 0 and p >= fraction and p < fraction + 0.25 then
      if prevT ~= nil and prevP ~= nil and prevP >= 0 and prevP < fraction and p > prevP then
        result = prevT + (t - prevT) * (fraction - prevP) / (p - prevP)
      else
        result = t
      end
      break
    end
    prevT, prevP = t, p
  end
  rec.cpCache[fraction] = result
  return result or nil
end

-- Markers drawn by script.draw3D when a slot has no loaded car model.
local fallbackMarkers = {}

-- ----------------------------------------------------------------------------
-- Per-frame update
-- ----------------------------------------------------------------------------

---@param dt number
---@param drivingActive boolean @True while a player's turn is running.
---@param waitingForLine boolean? @Driver hasn't crossed the line yet: ghosts wait at the start.
function M.update(dt, drivingActive, waitingForLine)
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
      -- Before the line the lap clock is meaningless (out-lap / post-teleport),
      -- so park the ghost on its first sample, like Trackmania's waiting ghost.
      local t = waitingForLine and target.rec.samples[1] or (car.lapTimeMs or 0)
      local pos, look, up = sampleAt(target.rec, t)
      if pos ~= nil then
        local slot = ensureSlot(i)
        if slot.loaded and slot.node then
          tintSlot(slot, target.color)
          -- Like Trackmania, the ghost car gets out of the way while it overlaps
          -- yours; its name tag stays so you still know where it is.
          local cp = car.position
          local near = cp ~= nil and (pos.x - cp.x) ^ 2 + (pos.y - cp.y) ^ 2 + (pos.z - cp.z) ^ 2 < HIDE_NEAR_M ^ 2
          local ok = pcall(function()
            slot.node:setPosition(pos)
            slot.node:setOrientation(look, up)
            slot.node:setVisible(not near)
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
