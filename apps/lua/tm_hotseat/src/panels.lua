-- UI for the main window: setup, handover, driving controls and results.
-- With the fullscreen Trackmania HUD on (default) this window is just the
-- control panel; with it off, the window shows the classic in-window standings.

local game = require('src/game')
local nicknames = require('src/nicknames')
local fmt = require('src/fmt')
local tm = require('src/tmui')
local settings = require('src/settings')
local controls = require('src/controls')
local overlay = require('src/overlay')

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

local fmtLap, fmtFuel, fmtClock = fmt.clock, fmt.fuel, fmt.clock

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

local function fuelBar(frac, height, color)
  frac = math.max(0, math.min(1, frac))
  local h = height or 14
  local ok = pcall(function()
    local p1 = ui.getCursor()
    local w = fullWidth()
    ui.drawRectFilled(p1, p1 + vec2(w, h), COL_BAR_BG, 3)
    -- Low fuel always warns red, otherwise use the requested (player) colour.
    local fill = (frac < 0.2 and COL_FUEL_LOW) or color or COL_FUEL_OK
    ui.drawRectFilled(p1, p1 + vec2(w * frac, h), fill, 3)
    ui.dummy(vec2(w, h))
  end)
  if not ok then ui.text(string.format('fuel %3d%%', frac * 100)) end
end

local function wideButton(label, h)
  return ui.button(label, vec2(fullWidth(), h or 36))
end

-- ----------------------------------------------------------------------------
-- Trackmania-style name-plates
-- ----------------------------------------------------------------------------

local playerColor = tm.playerColor

---Leader shows their absolute lap; everyone else shows +gap to the leader.
local function fmtGap(best, leaderBest)
  if best == nil then return '--:--.---' end
  if leaderBest == nil or best <= leaderBest then return fmtClock(best) end
  return '+' .. fmtClock(best - leaderBest)
end

local function measure(text)
  local ok, v = pcall(ui.measureText, text)
  if ok and v then return v end
  return vec2(#text * 8, 16)
end

local NAMEPLATE_H = 30

---One Trackmania leaderboard row: coloured plate whose fill = remaining fuel,
---name on the left, time/gap on the right. Everything past the plate itself is
---best-effort so the coloured bar still renders on odd CSP builds.
local function nameplate(name, fuelFrac, color, rightText, opts)
  opts = opts or {}
  local w = fullWidth()
  local h = NAMEPLATE_H
  local drew = pcall(function()
    local p1 = ui.getCursor()
    ui.drawRectFilled(p1, p1 + vec2(w, h), COL_BAR_BG, 4)
    local frac = math.max(0, math.min(1, fuelFrac or 0))
    if frac > 0.001 then
      ui.drawRectFilled(p1, p1 + vec2(w * frac, h), opts.dead and COL_DEAD or color, 4)
    end
    if opts.active then pcall(ui.drawRect, p1, p1 + vec2(w, h), rgbm(1, 1, 1, 0.9), 4, 2) end

    local textCol = opts.dead and COL_DIM or rgbm(1, 1, 1, 1)
    local label = (opts.marker and (opts.marker .. ' ') or '') .. name
    pcall(function()
      withFont(ui.Font.Title, function()
        local ts = measure(label)
        ui.setCursor(p1 + vec2(10, (h - ts.y) / 2))
        colText(label, textCol)
      end)
    end)
    pcall(function()
      withFont(ui.Font.Title, function()
        local ts = measure(rightText)
        ui.setCursor(p1 + vec2(math.max(10, w - ts.x - 10), (h - ts.y) / 2))
        colText(rightText, textCol)
      end)
    end)

    ui.setCursor(p1)
    ui.dummy(vec2(w, h))
  end)
  if not drew then
    colText(string.format('%-12s  %s', name, rightText), color)
    fuelBar(fuelFrac or 0, 6, color)
  end
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
  ui.text('Display')
  if ui.checkbox('Trackmania HUD (fullscreen overlay)', settings.hudOverlay) then
    settings.hudOverlay = not settings.hudOverlay
  end
  if settings.hudOverlay then
    if ui.button('-##scale') then settings.hudScale = math.max(0.6, settings.hudScale - 0.1) end
    ui.sameLine()
    ui.text(string.format('  HUD size %d%%  ', math.floor(settings.hudScale * 100 + 0.5)))
    ui.sameLine()
    if ui.button('+##scale') then settings.hudScale = math.min(2.0, settings.hudScale + 0.1) end
  end

  ui.separator()
  ui.text('Controls (keyboard, wheel or pad)')
  controls.drawBinding('Restart lap', controls.restart)
  controls.drawBinding('Ready (GO)', controls.ready)

  ui.separator()
  if wideButton('START GAME', 44) then game.startGame() end
end

-- ----------------------------------------------------------------------------
-- Player table (driving + handover + results)
-- ----------------------------------------------------------------------------

---Trackmania leaderboard: one coloured name-plate per player. When `showFuel`
---is set the plate fill tracks live fuel; otherwise it's a full solid plate.
local function drawStandings(showFuel)
  local s = game.state
  local leaderIdx = game.leaderIndex()
  local leaderBest = leaderIdx and s.players[leaderIdx].best or nil

  for _, e in ipairs(game.ranking()) do
    local p, idx = e.p, e.index
    nameplate(p.nick,
      showFuel and (p.fuel / p.fuelMax) or 1,
      playerColor(idx),
      fmtGap(p.best, leaderBest),
      { active = idx == s.current, marker = idx == leaderIdx and '👑' or nil })
  end

  local anyDead = false
  for idx, p in ipairs(s.players) do
    if p.eliminated then
      if not anyDead then
        anyDead = true
        ui.separator()
      end
      nameplate(p.nick, 0, playerColor(idx), fmtGap(p.best, leaderBest),
        { dead = true, marker = '✖' })
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
  fuelBar(p.fuel / p.fuelMax, nil, playerColor(s.current))
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
  if not settings.hudOverlay then
    ui.separator()
    drawStandings(false)
  end
end

-- ----------------------------------------------------------------------------
-- Driving HUD
-- ----------------------------------------------------------------------------

local COL_OVERTIME = rgbm(0.96, 0.55, 0.13, 1) -- amber "last chance" banner

---Big, hard-to-miss centred banner (used for cut-lap and overtime warnings).
local function banner(label, bg, hint)
  local w = fullWidth()
  local h = 36
  local ok = pcall(function()
    local p1 = ui.getCursor()
    ui.drawRectFilled(p1, p1 + vec2(w, h), bg, 4)
    withFont(ui.Font.Title, function()
      local ts = measure(label)
      ui.setCursor(p1 + vec2((w - ts.x) / 2, (h - ts.y) / 2))
      colText(label, rgbm(1, 1, 1, 1))
    end)
    ui.setCursor(p1)
    ui.dummy(vec2(w, h))
  end)
  if not ok then
    withFont(ui.Font.Title, function() colText(label, bg) end)
  end
  if hint then colText(hint, COL_DIM) end
end

local function drawRestartControls()
  if wideButton('RESTART LAP', 32) then game.requestRestart() end
  -- Optional hotkey; signature varies between CSP builds, hence the guard.
  pcall(function()
    if ui.keyboardButtonPressed(ui.KeyIndex.R) then game.requestRestart() end
  end)
end

---Control panel while the fullscreen HUD shows the race info.
local function drawDrivingCompact()
  local s = game.state
  local p = s.players[s.current]
  colText('ON THE WHEEL', COL_DIM)
  bigText(p.nick)
  ui.text('Fuel: ' .. fmtFuel(p.fuel) .. (s.overtime and '  (LAST CHANCE)' or ''))
  ui.separator()
  drawRestartControls()
  colText('Bind Restart to a wheel button in setup.', COL_DIM)
end

local function drawDriving()
  local s = game.state
  if settings.hudOverlay then
    drawDrivingCompact()
    return
  end

  -- Trackmania driving view: nothing but the leaderboard bars. The current
  -- driver's own bar shows their fuel draining, so no separate fuel readout.
  if s.overtime then
    banner('⛽ LAST CHANCE — NO FUEL', COL_OVERTIME, 'Finish this lap or restart to forfeit.')
    ui.separator()
  end
  if s.lapInvalid then
    banner('LAP INVALID — CUT', COL_FUEL_LOW, 'Restart or cross the line to reset.')
    ui.separator()
  end

  drawStandings(true)

  if s.mode == game.MODE_ELIMINATION then
    local above = game.playerAbove(s.current)
    if above then
      local target = s.players[above]
      colText('Beat ' .. target.nick .. ':  ' .. fmtLap(target.best), COL_FUEL_LOW)
    end
  end
  if s.message then colText(s.message, COL_GOLD) end

  ui.separator()
  drawRestartControls()

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
  if not settings.hudOverlay then
    ui.separator()
    drawStandings(false)
  end
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

  if settings.hudOverlay and overlay.lastError then
    ui.separator()
    colText('HUD error (untick the Trackmania HUD in setup to fall back):', COL_FUEL_LOW)
    pcall(ui.textWrapped, overlay.lastError)
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
