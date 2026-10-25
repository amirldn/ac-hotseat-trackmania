-- Time formatting shared by the window panels and the fullscreen HUD.

local M = {}

---MM:SS.mmm, e.g. 01:32.417 (Trackmania clock).
function M.clock(ms)
  if ms == nil then return '--:--.---' end
  local t = math.max(0, math.floor(ms))
  local m = math.floor(t / 60000)
  return string.format('%02d:%06.3f', m, (t - m * 60000) / 1000)
end

---M:SS for fuel budgets.
function M.fuel(seconds)
  local t = math.max(0, math.floor(seconds))
  return string.format('%d:%02d', math.floor(t / 60), t % 60)
end

---Signed split, e.g. -0.214 / +1.042 / +1:02.123.
function M.delta(ms)
  local sign = ms < 0 and '-' or '+'
  local t = math.floor(math.abs(ms) + 0.5)
  if t >= 60000 then
    local m = math.floor(t / 60000)
    return string.format('%s%d:%06.3f', sign, m, (t - m * 60000) / 1000)
  end
  return string.format('%s%.3f', sign, t / 1000)
end

return M
