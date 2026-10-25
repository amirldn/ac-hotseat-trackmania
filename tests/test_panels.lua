-- Smoke test: draws every window panel in every phase, in both HUD modes, against a
-- permissive ui stub (any unknown ui.* call is a no-op). Run from the repo root.
package.path = 'apps/lua/tm_hotseat/?.lua;' .. package.path
local failures = 0
local v2mt; local function V2(x, y) return setmetatable({ x = x or 0, y = y or 0 }, v2mt) end
v2mt = { __add = function(a, b) return V2(a.x + b.x, a.y + b.y) end }
vec2 = V2
function vec3(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
function rgbm(r, g, b, m) return { r = r, g = g, b = b, mult = m } end
stringify = setmetatable({ parse = function(s) return s end }, { __call = function(_, t) return t end })
local calls = {}
local bound, windowOpen = false, nil
ui = setmetatable({
  Font = { Title = 1, Huge = 2 }, KeyIndex = { R = 82 },
  getCursor = function() return V2(0, 0) end, availableSpaceX = function() return 300 end,
  measureText = function(t) return V2(#t * 7, 16) end,
}, { __index = function(_, k) return function() calls[k] = (calls[k] or 0) + 1 return false end end })
ui.DWriteFont = setmetatable({ Weight = {}, Style = {} }, { __call = function() local f = {} f.weight = function() return f end f.style = function() return f end return f end })
local car = { lapCount = 0, lapTimeMs = 0, previousLapTimeMs = 0, wheelsOutside = 0, position = vec3(), look = vec3(), up = vec3(), speedKmh = 0 }
ac = { getCar = function() return car end, getSim = function() return { trackLengthM = 3000 } end, storage = function(t) return t end,
  getUI = function() return { windowSize = V2(1920, 1080) } end,
  ControlButton = function() return { onPressed = function() end, control = function() end, configured = function() return bound end } end,
  setWindowOpen = function(_, open) windowOpen = open end }
physics = {}
local game = require('src/game')
local panels = require('src/panels')
local settings = require('src/settings')
require('src/controls').init(function() end)
local overlay = require('src/overlay')
local function drawAll(label)
  -- [classic] is the in-window fallback used when the overlay fails to draw.
  for _, overlayOn in ipairs({ true, false }) do
    overlay.lastError = not overlayOn and 'boom' or nil
    local ok, err = pcall(panels.drawMain, 0.016)
    if not ok then failures = failures + 1 end
    print((ok and 'PASS ' or 'FAIL ') .. label .. (overlayOn and ' [overlay]' or ' [classic]') .. (ok and '' or (': ' .. tostring(err))))
  end
  overlay.lastError = nil
end
drawAll('setup')
game.setup.playerCount = 3; game.startGame(); drawAll('handover')
game.confirmHandover(); drawAll('driving')
game.state.overtime, game.state.lapInvalid, game.state.message = true, true, 'hello'; drawAll('driving overtime+invalid')
for _, p in ipairs(game.state.players) do p.eliminated = true end
game.state.players[1].eliminated = false; game.state.players[1].best = 90000; game.state.phase = game.PHASE_OVER; drawAll('over')

local function check(name, cond)
  if not cond then failures = failures + 1 end
  print((cond and 'PASS ' or 'FAIL ') .. name)
end

-- START GAME only appears once GO / Restart is bound (drivers need it).
local buttons = {}
ui.button = function(label) buttons[label] = true return false end
game.resetGame(); buttons = {}; panels.drawMain(0.016)
check('setup: no START GAME while the button is unbound', not buttons['START GAME'])
bound = true; buttons = {}; panels.drawMain(0.016)
check('setup: START GAME once the button is bound', buttons['START GAME'] == true)
bound = false

-- Window auto-hide: only with the HUD on and a button bound, only on phase changes.
game.resetGame(); windowOpen = nil
panels.autoHideWindow()
check('window untouched on app load', windowOpen == nil)
game.setup.playerCount = 2; game.startGame(); panels.autoHideWindow()
check('window kept when no button is bound', windowOpen == nil)
game.resetGame(); panels.autoHideWindow(); bound = true
game.startGame(); panels.autoHideWindow()
check('window stays on the handover screen (GO + Abandon)', windowOpen == nil)
game.confirmHandover(); panels.autoHideWindow()
check('window closes when driving starts', windowOpen == false)
windowOpen = true; panels.autoHideWindow()
check('player reopening it mid-turn is respected', windowOpen == true)
windowOpen = false; game.state.phase = game.PHASE_HANDOVER; panels.autoHideWindow()
check('window reopens at the next handover', windowOpen == true)
game.confirmHandover(); panels.autoHideWindow()
game.state.phase = game.PHASE_OVER; panels.autoHideWindow()
check('window reopens for results', windowOpen == true)

print(failures == 0 and '\nALL TESTS PASSED' or ('\n' .. failures .. ' FAILURES'))
os.exit(failures == 0 and 0 or 1)
