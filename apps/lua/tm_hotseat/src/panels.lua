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

-- Stable per-player colours (keyed by the player's slot index, not their rank).
local PLAYER_COLORS = {
  rgbm(0.60, 0.25, 0.85, 1), -- violet
  rgbm(0.93, 0.82, 0.15, 1), -- yellow
  rgbm(0.28, 0.78, 0.32, 1), -- green
  rgbm(0.90, 0.20, 0.18, 1), -- red
  rgbm(0.96, 0.55, 0.13, 1), -- orange
  rgbm(0.26, 0.68, 0.95, 1), -- blue
  rgbm(0.80, 0.62, 0.42, 1), -- tan
  rgbm(0.62, 0.64, 0.70, 1), -- steel
}

local function playerColor(idx)
  return PLAYER_COLORS[(idx - 1) % #PLAYER_COLORS + 1]
end

---MM:SS.mmm, e.g. 00:15.673 (Trackmania leaderboard clock).
local function fmtClock(ms)
  local t = math.max(0, math.floor(ms))
  local m = math.floor(t / 60000)
  return string.format('%02d:%06.3f', m, (t - m * 60000) / 1000)
end

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
  ui.separator()
  drawStandings(false)
end

-- ----------------------------------------------------------------------------
-- Driving HUD
-- ----------------------------------------------------------------------------

---Big, hard-to-miss red banner shown while the current lap is voided.
local function invalidBanner()
  local w = fullWidth()
  local h = 36
  local ok = pcall(function()
    local p1 = ui.getCursor()
    ui.drawRectFilled(p1, p1 + vec2(w, h), COL_FUEL_LOW, 4)
    withFont(ui.Font.Title, function()
      local label = 'LAP INVALID — CUT'
      local ts = measure(label)
      ui.setCursor(p1 + vec2((w - ts.x) / 2, (h - ts.y) / 2))
      colText(label, rgbm(1, 1, 1, 1))
    end)
    ui.setCursor(p1)
    ui.dummy(vec2(w, h))
  end)
  if not ok then
    withFont(ui.Font.Title, function() colText('LAP INVALID — CUT', COL_FUEL_LOW) end)
  end
  colText('Restart or cross the line to reset.', COL_DIM)
end

local function drawDriving()
  local s = game.state

  -- Trackmania driving view: nothing but the leaderboard bars. The current
  -- driver's own bar shows their fuel draining, so no separate fuel readout.
  if s.lapInvalid then
    invalidBanner()
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
  if wideButton('RESTART LAP', 32) then game.requestRestart() end
  -- Optional hotkey; signature varies between CSP builds, hence the guard.
  pcall(function()
    if ui.keyboardButtonPressed(ui.KeyIndex.R) then game.requestRestart() end
  end)

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
