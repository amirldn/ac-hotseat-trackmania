-- Renders the real overlay.lua through a stubbed CSP ui API into SVG frames, so
-- HUD layout changes can be checked without launching Assetto Corsa. Text widths
-- are approximated (no DirectWrite here), so expect small spacing differences.
-- Usage (from the repo root): luajit tools/render_hud_preview.lua <out_dir>
-- then e.g. rsvg-convert -w 1200 <out_dir>/3_handover.svg -o handover.png
local outDir = arg[1]
package.path = 'apps/lua/tm_hotseat/?.lua;' .. package.path

local v2mt
local function V2(x, y) return setmetatable({ x = x or 0, y = y or 0 }, v2mt) end
v2mt = { __add = function(a, b) return V2(a.x + b.x, a.y + b.y) end, __sub = function(a, b) return V2(a.x - b.x, a.y - b.y) end }
vec2 = V2
local v3mt
v3mt = { __index = { set = function(s, x, y, z) s.x, s.y, s.z = x, y, z return s end,
  clone = function(s) return setmetatable({ x = s.x, y = s.y, z = s.z }, v3mt) end },
  __add = function(a, b) return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, v3mt) end }
function vec3(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, v3mt) end
function rgbm(r, g, b, m) return { r = r, g = g, b = b, mult = m } end
stringify = setmetatable({ parse = function(s) return s end }, { __call = function(_, t) return t end })

local W, H = 1600, 900
local ops, path = {}, {}
local function col(c) return string.format('rgba(%d,%d,%d,%.2f)', c.r * 255, c.g * 255, c.b * 255, c.mult or 1) end
local function esc(t) return (tostring(t):gsub('&', '&amp;'):gsub('<', '&lt;')) end
local CHAR_W = 0.60 -- approx advance of Segoe UI Black Italic, caps-heavy text

ui = {
  DWriteFont = setmetatable({ Weight = { Black = 'Black' }, Style = { Italic = 'Italic' } }, {
    __call = function() local f = {} f.weight = function() return f end f.style = function() return f end return f end }),
  pushDWriteFont = function() end, popDWriteFont = function() end,
  pathLineTo = function(p) path[#path + 1] = string.format('%.1f,%.1f', p.x, p.y) end,
  pathFillConvex = function(c) ops[#ops + 1] = string.format('<polygon points="%s" fill="%s"/>', table.concat(path, ' '), col(c)) path = {} end,
  drawRectFilled = function(a, b, c) ops[#ops + 1] = string.format('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s"/>', a.x, a.y, b.x - a.x, b.y - a.y, col(c)) end,
  measureDWriteText = function(t, size) return V2(#tostring(t) * size * CHAR_W, size * 1.25) end,
  dwriteDrawText = function(t, size, p, c)
    ops[#ops + 1] = string.format('<text x="%.1f" y="%.1f" font-size="%.1f" fill="%s" font-family="Segoe UI, Arial" font-weight="900" font-style="italic" textLength="%.1f" lengthAdjust="spacingAndGlyphs">%s</text>',
      p.x, p.y + size * 1.0, size, col(c), #tostring(t) * size * CHAR_W, esc(t))
  end,
}

local car = { lapCount = 3, lapTimeMs = 41873, previousLapTimeMs = 0, wheelsOutside = 0, position = vec3(), look = vec3(0, 0, 1), up = vec3(0, 1, 0), speedKmh = 140, splinePosition = 0.42 }
ac = {
  getCar = function() return car end,
  getSim = function() return { trackLengthM = 5400 } end,
  getUI = function() return { windowSize = V2(W, H) } end,
  storage = function(t) return t end,
  ControlButton = function() return { onPressed = function() end, configured = function() return true end } end,
}
physics = {}

local game = require('src/game')
local overlay = require('src/overlay')
require('src/controls').init({ restart = function() end, ready = function() end })

local function players()
  game.state.players = {
    { nick = 'Badger', fuel = 214, fuelMax = 330, best = 92417, bestStamp = 1, eliminated = false },
    { nick = 'Quokka', fuel = 118, fuelMax = 330, best = 93006, bestStamp = 2, eliminated = false },
    { nick = 'Narwhal', fuel = 61, fuelMax = 330, best = 94873, bestStamp = 3, eliminated = false },
    { nick = 'Platypus', fuel = 0, fuelMax = 330, best = 97552, bestStamp = 4, eliminated = true },
  }
end

local frames = {}
local function frame(name, setup)
  ops = {}
  setup()
  overlay.draw()
  if overlay.lastError then print('ERROR in ' .. name .. ': ' .. overlay.lastError) end
  frames[#frames + 1] = name
  local f = assert(io.open(outDir .. '/' .. name .. '.svg', 'w'))
  -- fake track backdrop: sky, tarmac, kerbs
  f:write(string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">', W, H))
  f:write('<defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#6d8fb3"/><stop offset="1" stop-color="#b9cbd9"/></linearGradient></defs>')
  f:write(string.format('<rect width="%d" height="%d" fill="url(#sky)"/>', W, H * 0.45))
  f:write(string.format('<rect y="%d" width="%d" height="%d" fill="#4d6b3c"/>', H * 0.45, W, H * 0.55))
  f:write(string.format('<polygon points="%d,%d %d,%d %d,%d %d,%d" fill="#3b3e44"/>', W * 0.42, H * 0.45, W * 0.58, H * 0.45, W * 0.95, H, W * 0.05, H))
  f:write(table.concat(ops, '\n'))
  f:write('</svg>')
  f:close()
end

frame('1_driving_elimination', function()
  players()
  game.state.phase, game.state.mode, game.state.current = game.PHASE_DRIVING, game.MODE_ELIMINATION, 3
  game.state.lapDirty, game.state.lapInvalid, game.state.overtime = false, false, false
  game.clock = 10
  game.state.split = { cp = 2, n = 7, time = 24311, delta = -214, at = 9 }
  game.state.message = nil
end)

frame('2_driving_invalid_overtime', function()
  players()
  game.state.phase, game.state.mode, game.state.current = game.PHASE_DRIVING, game.MODE_ELIMINATION, 3
  game.state.players[3].fuel = 0
  game.state.lapInvalid, game.state.overtime = true, true
  game.state.split = { cp = 5, n = 7, time = 61200, delta = 1042, at = 9.5 }
end)

frame('3_handover', function()
  players()
  game.state.phase, game.state.mode, game.state.current = game.PHASE_HANDOVER, game.MODE_ELIMINATION, 2
  game.state.lapInvalid, game.state.overtime = false, false
  game.state.lastLap = { nick = 'Narwhal', time = 92800, delta = -206, vsNick = 'Quokka' }
end)

frame('4_opening_waiting', function()
  players()
  for i = 2, 4 do game.state.players[i].best = nil game.state.players[i].eliminated = false game.state.players[i].fuel = 330 end
  game.state.phase, game.state.mode, game.state.current = game.PHASE_DRIVING, game.MODE_OPENING, 2
  game.state.lapDirty = true
  game.state.split = nil
end)

frame('5_winner', function()
  players()
  game.state.players[2].eliminated, game.state.players[3].eliminated = true, true; game.state.players[2].outOrder = 3; game.state.players[3].outOrder = 2; game.state.players[4].outOrder = 1
  game.state.phase, game.state.current = game.PHASE_OVER, nil
end)

print(table.concat(frames, ' '))
