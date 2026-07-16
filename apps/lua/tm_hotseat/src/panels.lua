-- UI for the main window: setup, handover, driving HUD and results.
-- Dock the window in the top-left corner for the classic hotseat layout.

local game = require('src/game')
local ghosts = require('src/ghosts')
local nicknames = require('src/nicknames')

local M = {}

local COL_FUEL_OK = rgbm(0.3, 0.85, 0.4, 1)
local COL_FUEL_LOW = rgbm(0.95, 0.35, 0.2, 1)
local COL_BAR_BG = rgbm(0.16, 0.16, 0.16, 0.9)
local COL_GOLD = rgbm(1, 0.85, 0.2, 1)
local COL_CURRENT = rgbm(0.4, 0.8, 1, 1)
local COL_DEAD = rgbm(0.55, 0.55, 0.55, 1)
local COL_DIM = rgbm(0.7, 0.7, 0.7, 1)

-- ----------------------------------------------------------------------------
-- Small helpers (guarded where CSP builds differ)
-- ----------------------------------------------------------------------------

local function fmtLap(ms)
  if ms == nil then return '--:--.---' end
  local t = math.floor(ms)
  local m = math.floor(t / 60000)
  local s = math.floor(t / 1000) % 60
  local r = t % 1000
  return string.format('%d:%02d.%03d', m, s, r)
end

local function fmtFuel(seconds)
  local t = math.max(0, math.floor(seconds))
  return string.format('%d:%02d', math.floor(t / 60), t % 60)
end

local function colText(text, color)
  if not pcall(ui.textColored, text, color) then ui.text(text) end
end

local function withFont(font, fn)
  local pushed = pcall(ui.pushFont, font)
  fn()
  if pushed then pcall(ui.popFont) end
end

local function bigText(text) withFont(ui.Font.Title, function() ui.text(text) end) end
local function hugeText(text) withFont(ui.Font.Huge, function() ui.text(text) end) end

local function fullWidth()
  local ok, w = pcall(ui.availableSpaceX)
  return ok and w or 320
end

local function fuelBar(frac, height)
  frac = math.max(0, math.min(1, frac))
  local h = height or 14
  local ok = pcall(function()
    local p1 = ui.getCursor()
    local w = fullWidth()
    ui.drawRectFilled(p1, p1 + vec2(w, h), COL_BAR_BG, 3)
    ui.drawRectFilled(p1, p1 + vec2(w * frac, h), frac < 0.2 and COL_FUEL_LOW or COL_FUEL_OK, 3)
    ui.dummy(vec2(w, h))
  end)
  if not ok then ui.text(string.format('fuel %3d%%', frac * 100)) end
end

local function wideButton(label, h)
  return ui.button(label, vec2(fullWidth(), h or 36))
end

-- ----------------------------------------------------------------------------
-- Setup
-- ----------------------------------------------------------------------------

local function drawSetup()
  bigText('TM Hotseat')
  ui.text('Take turns on one PC. Worst lap drives.')
  ui.text('Run out of fuel and you are out.')
  ui.separator()

  if game.setup.fuelSeconds == nil then
    game.setup.fuelSeconds = game.defaultFuelSeconds()
  end

  ui.text('Players')
  if ui.button(' - ##players') and game.setup.playerCount > 2 then
    game.setup.playerCount = game.setup.playerCount - 1
  end
  ui.sameLine()
  ui.text(string.format('  %d  ', game.setup.playerCount))
  ui.sameLine()
  if ui.button(' + ##players') and game.setup.playerCount < 8 then
    game.setup.playerCount = game.setup.playerCount + 1
  end

  ui.separator()
  ui.text('Nickname category')
  for i, cat in ipairs(nicknames.categories) do
    local marker = i == game.setup.categoryIndex and '● ' or '○ '
    if ui.button(marker .. cat.name .. '##cat' .. i) then
      game.setup.categoryIndex = i
    end
  end

  ui.separator()
  ui.text(string.format('Fuel per player (track: %.1f km)', game.trackLengthKm()))
  if ui.button('-30s##fuel') then
    game.setup.fuelSeconds = math.max(game.cfg.minFuelS, game.setup.fuelSeconds - game.cfg.fuelStepS)
  end
  ui.sameLine()
  ui.text('  ' .. fmtFuel(game.setup.fuelSeconds) .. '  ')
  ui.sameLine()
  if ui.button('+30s##fuel') then
    game.setup.fuelSeconds = math.min(game.cfg.maxFuelS, game.setup.fuelSeconds + game.cfg.fuelStepS)
  end
  ui.sameLine()
  if ui.button('Auto##fuel') then game.setup.fuelSeconds = game.defaultFuelSeconds() end

  ui.separator()
  if wideButton('START GAME', 44) then game.startGame() end
end

-- ----------------------------------------------------------------------------
-- Player table (driving + handover + results)
-- ----------------------------------------------------------------------------

local function drawStandings(showFuelBars)
  local s = game.state
  local leader = game.leaderIndex()
  for pos, e in ipairs(game.ranking()) do
    local p, idx = e.p, e.index
    local tag = idx == s.current and '▶' or (idx == leader and '👑' or ' ')
    local color = idx == s.current and COL_CURRENT or (idx == leader and COL_GOLD or nil)
    local line = string.format('%s %d. %-12s %s', tag, pos, p.nick, fmtLap(p.best))
    if color then colText(line, color) else ui.text(line) end
    if showFuelBars then fuelBar(p.fuel / p.fuelMax, 6) end
  end
  local anyDead = false
  for _, p in ipairs(s.players) do
    if p.eliminated then
      if not anyDead then
        anyDead = true
        ui.separator()
      end
      colText(string.format('✖ %-12s %s', p.nick, fmtLap(p.best)), COL_DEAD)
    end
  end
end

-- ----------------------------------------------------------------------------
-- Handover
-- ----------------------------------------------------------------------------

local function drawHandover()
  local s = game.state
  local p = s.players[s.current]
  colText('PASS THE WHEEL TO', COL_DIM)
  hugeText(p.nick)
  ui.separator()
  ui.text('Fuel remaining: ' .. fmtFuel(p.fuel))
  fuelBar(p.fuel / p.fuelMax)
  if s.mode == game.MODE_OPENING then
    ui.text('Goal: set one valid lap.')
  else
    local above = game.playerAbove(s.current)
    if above then
      local target = s.players[above]
      ui.text('Beat ' .. target.nick .. ' to survive:')
      bigText(fmtLap(target.best))
    end
  end
  ui.separator()
  if wideButton('GO — I AM READY', 48) then game.confirmHandover() end
  ui.separator()
  drawStandings(false)
end

-- ----------------------------------------------------------------------------
-- Driving HUD
-- ----------------------------------------------------------------------------

local function drawDriving()
  local s = game.state
  local p = s.players[s.current]
  colText('NOW DRIVING', COL_DIM)
  bigText(p.nick)

  ui.text('Fuel  ' .. fmtFuel(p.fuel))
  fuelBar(p.fuel / p.fuelMax)

  if s.mode == game.MODE_ELIMINATION then
    local above = game.playerAbove(s.current)
    if above then
      local target = s.players[above]
      colText('Beat ' .. target.nick .. ':  ' .. fmtLap(target.best), COL_FUEL_LOW)
    end
  else
    ui.text('Set one valid lap to bank your fuel.')
  end
  if p.best then ui.text('Your best:  ' .. fmtLap(p.best)) end
  if s.lapInvalid then colText('LAP INVALID — cut track. Restart or cross the line.', COL_FUEL_LOW) end
  if s.message then colText(s.message, COL_GOLD) end

  if wideButton('RESTART LAP (fuel keeps draining)', 32) then game.requestRestart() end
  -- Optional hotkey; signature varies between CSP builds, hence the guard.
  pcall(function()
    if ui.keyboardButtonPressed(ui.KeyIndex.R) then game.requestRestart() end
  end)

  ui.separator()
  drawStandings(true)

  local targets = game.getGhostTargets()
  if #targets > 0 then
    ui.separator()
    colText('Ghosts on track:', COL_DIM)
    for _, t in ipairs(targets) do ui.text('  ' .. t.label) end
  end
end

-- ----------------------------------------------------------------------------
-- Results
-- ----------------------------------------------------------------------------

local function drawOver()
  local s = game.state
  local winner = nil
  for _, p in ipairs(s.players) do
    if not p.eliminated then winner = p break end
  end
  colText('WINNER', COL_GOLD)
  hugeText(winner and winner.nick or '—')
  if winner and winner.best then bigText(fmtLap(winner.best)) end
  ui.separator()
  drawStandings(false)
  ui.separator()
  if wideButton('NEW GAME', 40) then game.resetGame() end
end

-- ----------------------------------------------------------------------------

local confirmReset = 0

function M.drawMain(dt)
  local phase = game.state.phase
  if phase == game.PHASE_SETUP then
    drawSetup()
  elseif phase == game.PHASE_HANDOVER then
    drawHandover()
  elseif phase == game.PHASE_DRIVING then
    drawDriving()
  else
    drawOver()
  end

  if phase ~= game.PHASE_SETUP then
    ui.separator()
    if confirmReset > 0 then
      if ui.button('Really abandon game?##reset') then
        game.resetGame()
        confirmReset = 0
      end
      confirmReset = confirmReset - dt
    elseif ui.button('Abandon game##reset') then
      confirmReset = 3
    end
  end
end

return M
