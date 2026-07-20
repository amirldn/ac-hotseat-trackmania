-- Simple 2D UI sound cues. Everything is guarded: on a CSP build that can't
-- load the audio (or in the headless test where ac.AudioEvent is absent) the
-- calls just no-op instead of erroring.

local M = {}

-- One-shot events become invalid after playing once, so we make a fresh one per
-- cue and keep a bounded pool of recent ones alive long enough to finish (CSP
-- keeps events alive until disposed). The oldest is disposed once the pool fills.
local pool = {}
local MAX_ALIVE = 8

local function play(file, volume)
  pcall(function()
    local ev = ac.AudioEvent.fromFile({ filename = file, use3D = false, loop = false }, false)
    ev.volume = volume or 1
    ev:resume()
    pool[#pool + 1] = ev
    if #pool > MAX_ALIVE then
      local old = table.remove(pool, 1)
      pcall(function() old:dispose() end)
    end
  end)
end

---Cut/void-lap warning (low descending buzz).
function M.invalid() play('sfx/invalid.wav', 1) end

---Wheel passes to the next player (bright ascending chime).
function M.next() play('sfx/next.wav', 1) end

return M
