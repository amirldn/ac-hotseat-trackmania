-- Trackmania (2020) drawing kit for the fullscreen HUD: right-leaning
-- parallelogram slabs, heavy italic type, white-on-dark translucent panels.
-- All sizes are in screen pixels; callers apply the HUD scale.

local M = {}

-- Palette
M.white     = rgbm(1.00, 1.00, 1.00, 0.97)
M.dim       = rgbm(1.00, 1.00, 1.00, 0.55)
M.panel     = rgbm(0.06, 0.07, 0.11, 0.82) -- dark slab
M.panelDeep = rgbm(0.02, 0.02, 0.05, 0.90) -- darker slab (times, chips)
M.green     = rgbm(0.00, 0.80, 0.33, 1.00) -- TM accent green
M.gold      = rgbm(1.00, 0.76, 0.10, 1.00)
M.silver    = rgbm(0.76, 0.80, 0.86, 1.00)
M.bronze    = rgbm(0.80, 0.52, 0.26, 1.00)
M.red       = rgbm(0.90, 0.13, 0.20, 1.00)
M.amber     = rgbm(0.96, 0.55, 0.13, 1.00)
M.ahead     = rgbm(0.10, 0.45, 1.00, 0.95) -- split chip: ahead of target (TM blue)
M.behind    = rgbm(0.90, 0.13, 0.20, 0.95) -- split chip: behind target (TM red)

-- Stable per-player colours (keyed by the player's slot index, not their rank).
M.PLAYER_COLORS = {
  rgbm(0.60, 0.25, 0.85, 1), -- violet
  rgbm(0.93, 0.82, 0.15, 1), -- yellow
  rgbm(0.28, 0.78, 0.32, 1), -- green
  rgbm(0.90, 0.20, 0.18, 1), -- red
  rgbm(0.96, 0.55, 0.13, 1), -- orange
  rgbm(0.26, 0.68, 0.95, 1), -- blue
  rgbm(0.80, 0.62, 0.42, 1), -- tan
  rgbm(0.62, 0.64, 0.70, 1), -- steel
}

function M.playerColor(idx)
  return M.PLAYER_COLORS[(idx - 1) % #M.PLAYER_COLORS + 1]
end

-- Horizontal lean per unit of height (~15°).
M.SKEW = 0.27

local fontOk, font = pcall(function()
  return ui.DWriteFont('Segoe UI'):weight(ui.DWriteFont.Weight.Black):style(ui.DWriteFont.Style.Italic)
end)

local function pushFont() if fontOk then pcall(ui.pushDWriteFont, font) end end
local function popFont() if fontOk then pcall(ui.popDWriteFont) end end

function M.alpha(c, a) return rgbm(c.r, c.g, c.b, a) end

function M.lighten(c, k)
  return rgbm(math.min(1, c.r + k), math.min(1, c.g + k), math.min(1, c.b + k), c.mult)
end

---Right-leaning parallelogram whose bounding box starts at `p`. Painted width
---is w + h * SKEW (the top edge is shifted right).
function M.slab(p, w, h, color)
  if w <= 0 then return end
  local k = h * M.SKEW
  ui.pathLineTo(vec2(p.x + k, p.y))
  ui.pathLineTo(vec2(p.x + w + k, p.y))
  ui.pathLineTo(vec2(p.x + w, p.y + h))
  ui.pathLineTo(vec2(p.x, p.y + h))
  ui.pathFillConvex(color)
end

function M.measure(text, size)
  pushFont()
  local v = ui.measureDWriteText(text, size)
  popFont()
  return v
end

function M.text(text, size, p, color)
  pushFont()
  ui.dwriteDrawText(text, size, p, color)
  popFont()
end

---Text inside a slab of height h: align = 0 left, 0.5 centre, 1 right.
---Accounts for the lean so text sits visually centred in the parallelogram.
function M.slabText(text, size, p, w, h, color, align, pad)
  pad = pad or h * 0.35
  local ts = M.measure(text, size)
  local lean = h * M.SKEW * 0.5
  local x
  if align == 1 then
    x = p.x + w - ts.x - pad + lean
  elseif align == 0.5 then
    x = p.x + (w - ts.x) / 2 + lean
  else
    x = p.x + pad + lean
  end
  M.text(text, size, vec2(x, p.y + (h - ts.y) / 2), color)
end

---Slab with text — the basic TM chip.
function M.chip(p, w, h, bg, text, size, fg, align)
  M.slab(p, w, h, bg)
  if text and text ~= '' then M.slabText(text, size, p, w, h, fg or M.white, align or 0.5) end
end

---Chip sized to its text, centred horizontally on cx. Returns the bottom y.
function M.centerChip(cx, y, text, size, bg, fg, padX, padY)
  local ts = M.measure(text, size)
  padX, padY = padX or size * 0.9, padY or size * 0.28
  local h = ts.y + padY * 2
  local w = ts.x + padX * 2
  local p = vec2(cx - (w + h * M.SKEW) / 2, y)
  M.chip(p, w, h, bg, text, size, fg)
  return y + h
end

---Skewed gauge: track + fill.
function M.gauge(p, w, h, frac, color)
  M.slab(p, w, h, rgbm(1, 1, 1, 0.12))
  frac = math.max(0, math.min(1, frac))
  if frac > 0.002 then M.slab(p, w * frac, h, color) end
end

function M.fuelColor(frac)
  if frac > 0.5 then return M.green end
  if frac > 0.2 then return M.gold end
  return M.red
end

return M
