-- Fullscreen Trackmania HUD (CSP IN_GAME UI callback), drawn straight onto the
-- screen with no window chrome:
--   top-left       hotseat leaderboard — player-coloured plates drain with fuel
--   bottom-centre  lap clock, checkpoint splits vs your target, fuel gauge
--   top-centre     LAP INVALID / LAST CHANCE banners
--   centre         handover card ("pass the wheel to …") and the winner card
-- Everything scales with screen height (1080p = 1.0) times the HUD scale setting.

local game = require('src/game')
local fmt = require('src/fmt')
local tm = require('src/tmui')
local settings = require('src/settings')
local controls = require('src/controls')

local M = {}

---Last error raised while drawing, surfaced in the app window for debugging.
M.lastError = nil

local function screenSize()
  local ok, v = pcall(function() return ac.getUI().windowSize end)
  if ok and v and v.x > 0 then return vec2(v.x, v.y) end
  return vec2(1920, 1080)
end

local function up(s) return string.upper(tostring(s)) end

local function modeHeader()
  local s = game.state
  if s.phase == game.PHASE_OVER then return 'FINAL STANDINGS', tm.gold end
  if s.mode == game.MODE_ELIMINATION then return 'ELIMINATION', tm.red end
  return 'OPENING ROUND', tm.green
end

local function gapText(best, leaderBest)
  if best == nil then return '--:--.---' end
  if leaderBest == nil or best <= leaderBest then return fmt.clock(best) end
  return fmt.delta(best - leaderBest)
end

-- ----------------------------------------------------------------------------
-- Leaderboard (top-left)
-- ----------------------------------------------------------------------------

local function leaderboard(S)
  local s = game.state
  local driving = s.phase == game.PHASE_DRIVING
  local x, y = 24 * S, 24 * S
  local rowH, gap = 30 * S, 4 * S
  local rankW, nameW, timeW = 36 * S, 196 * S, 116 * S
  local totalW = rankW + gap + nameW + gap + timeW

  local label, color = modeHeader()
  local headH = 26 * S
  tm.chip(vec2(x, y), totalW * 0.6, headH, color, label, 15 * S, tm.white, 0)
  tm.chip(vec2(x + totalW * 0.6 + gap, y), totalW * 0.4 - gap, headH, tm.panelDeep, 'HOTSEAT', 13 * S, tm.dim)
  y = y + headH + gap * 2

  local leaderIdx = game.leaderIndex()
  local leaderBest = leaderIdx and s.players[leaderIdx].best or nil
  local targetIdx = s.phase ~= game.PHASE_OVER and game.splitTargetIndex() or nil

  local function row(pos, idx, p, dead)
    local active = idx == s.current and s.phase ~= game.PHASE_OVER
    local rx = x
    -- rank chip: white = on the wheel, gold = leader
    local over = s.phase == game.PHASE_OVER
    local rankBg, rankFg = tm.panelDeep, tm.white
    if dead then rankBg = over and ({ tm.silver, tm.bronze })[pos - 1] or tm.alpha(tm.red, 0.55)
    elseif active then rankBg, rankFg = tm.white, rgbm(0.05, 0.05, 0.08, 1)
    elseif idx == leaderIdx then rankBg = tm.gold end
    local rankText = p.best and tostring(pos) or '-'
    if dead then rankText = over and tostring(pos) or 'X' end
    tm.chip(vec2(rx, y), rankW, rowH, rankBg, rankText, 16 * S, rankFg)
    rx = rx + rankW + gap

    -- name plate: player colour fill tracks remaining fuel (Trackmania hotseat bars)
    tm.slab(vec2(rx, y), nameW, rowH, dead and tm.alpha(tm.panel, 0.45) or tm.panel)
    if not dead then
      local frac = driving and math.max(0, math.min(1, p.fuel / p.fuelMax)) or 1
      tm.slab(vec2(rx, y), nameW * frac, rowH, tm.alpha(tm.playerColor(idx), active and 0.95 or 0.75))
    end
    tm.slabText(up(p.nick), 16 * S, vec2(rx, y), nameW, rowH, dead and tm.dim or tm.white, 0)
    rx = rx + nameW + gap

    -- time / gap to leader; the time you must beat is gold
    tm.slab(vec2(rx, y), timeW, rowH, tm.alpha(tm.panelDeep, dead and 0.45 or 0.9))
    local tcol = tm.white
    if dead then tcol = tm.dim elseif idx == targetIdx then tcol = tm.gold end
    tm.slabText(gapText(p.best, leaderBest), 15 * S, vec2(rx, y), timeW, rowH, tcol, 1)
    y = y + rowH + gap
  end

  local ranking = game.ranking()
  for pos, e in ipairs(ranking) do row(pos, e.index, e.p, false) end
  -- Eliminated players below, most recently out first (= their final place).
  local dead = {}
  for idx, p in ipairs(s.players) do
    if p.eliminated then dead[#dead + 1] = idx end
  end
  table.sort(dead, function(a, b) return (s.players[a].outOrder or 0) > (s.players[b].outOrder or 0) end)
  if #dead > 0 then y = y + gap * 2 end
  for i, idx in ipairs(dead) do row(#ranking + i, idx, s.players[idx], true) end
end

-- ----------------------------------------------------------------------------
-- Driving HUD (bottom-centre + banners)
-- ----------------------------------------------------------------------------

local function splitVisible(split)
  return split ~= nil and game.clock - (split.at or -1e9) < game.cfg.splitShowS
end

local function driveHud(S, scr)
  local s = game.state
  local p = s.players[s.current]
  local car = ac.getCar(0)
  if p == nil or car == nil then return end
  local cx = scr.x / 2

  -- lap clock
  local timerW, timerH = 250 * S, 56 * S
  local tp = vec2(cx - (timerW + timerH * tm.SKEW) / 2, scr.y - 132 * S)
  local waiting = game.waitingForLine()
  local clockCol = tm.white
  if waiting then clockCol = tm.dim elseif s.lapInvalid then clockCol = tm.red end
  tm.chip(tp, timerW, timerH, tm.panel, waiting and '--:--.---' or fmt.clock(car.lapTimeMs), 38 * S, clockCol)

  -- above the clock: checkpoint split (TM blue = ahead, red = behind) or a hint
  local aboveY = tp.y - 36 * S
  if waiting then
    tm.centerChip(cx, aboveY + 4 * S, 'CROSS THE LINE TO START', 14 * S, tm.panelDeep, tm.dim)
  elseif splitVisible(s.split) then
    local sp = s.split
    local label = sp.final and 'FINISH' or string.format('CP %d/%d', sp.cp, sp.n)
    local h = 30 * S
    local lw, dw = 86 * S, 110 * S
    local left = cx - (lw + 4 * S + dw + h * tm.SKEW) / 2
    tm.chip(vec2(left, aboveY), lw, h, tm.panelDeep, label, 14 * S, tm.white)
    if sp.delta ~= nil then
      local bg = sp.delta < 0 and tm.ahead or (sp.delta > 0 and tm.behind or tm.panelDeep)
      tm.chip(vec2(left + lw + 4 * S, aboveY), dw, h, bg, fmt.delta(sp.delta), 17 * S, tm.white)
    else
      tm.chip(vec2(left + lw + 4 * S, aboveY), dw, h, tm.panel, fmt.clock(sp.time), 15 * S, tm.white)
    end
  end

  -- fuel gauge under the clock; chip to the right
  local frac = math.max(0, math.min(1, p.fuel / p.fuelMax))
  local fuelCol = s.overtime and tm.amber or tm.fuelColor(frac)
  tm.gauge(vec2(tp.x, tp.y + timerH + 6 * S), timerW, 8 * S, frac, fuelCol)
  local chipH = 26 * S
  local rightX = tp.x + timerW + timerH * tm.SKEW + 8 * S
  tm.chip(vec2(rightX, tp.y + (timerH - chipH) / 2), 120 * S, chipH, tm.panelDeep,
    s.overtime and 'NO FUEL' or ('FUEL ' .. fmt.fuel(p.fuel)), 14 * S, fuelCol)

  -- target to the left of the clock
  local targetIdx = game.splitTargetIndex()
  local target = targetIdx and s.players[targetIdx] or nil
  if target and target.best then
    local prefix = s.mode == game.MODE_ELIMINATION and 'BEAT ' or 'LEADER '
    local text = prefix .. up(target.nick) .. '  ' .. fmt.clock(target.best)
    local ts = tm.measure(text, 14 * S)
    local w = ts.x + 26 * S
    tm.chip(vec2(tp.x - 8 * S - w - chipH * tm.SKEW, tp.y + (timerH - chipH) / 2), w, chipH, tm.panelDeep,
      text, 14 * S, s.mode == game.MODE_ELIMINATION and tm.gold or tm.white)
  end

  -- banners
  local by = scr.y * 0.15
  if s.overtime then
    by = tm.centerChip(cx, by, 'LAST CHANCE — FINISH THIS LAP', 26 * S, tm.alpha(tm.amber, 0.92), tm.white) + 6 * S
  end
  if s.lapInvalid then
    by = tm.centerChip(cx, by, 'LAP INVALID', 30 * S, tm.alpha(tm.red, 0.92), tm.white) + 6 * S
    by = tm.centerChip(cx, by, 'RESTART OR CROSS THE LINE', 13 * S, tm.panelDeep, tm.dim) + 6 * S
  end
  if s.message then
    tm.centerChip(cx, by, up(s.message), 15 * S, tm.panelDeep, tm.gold)
  end
end

-- ----------------------------------------------------------------------------
-- Handover and winner cards
-- ----------------------------------------------------------------------------

local function handoverCard(S, scr)
  local s = game.state
  local p = s.players[s.current]
  if p == nil then return end
  local cx = scr.x / 2
  local label, color = modeHeader()
  local y = scr.y * 0.24

  y = tm.centerChip(cx, y, label, 20 * S, color, tm.white) + 14 * S
  y = tm.centerChip(cx, y, 'PASS THE WHEEL TO', 18 * S, tm.panelDeep, tm.dim) + 6 * S
  y = tm.centerChip(cx, y, up(p.nick), 76 * S, tm.panel, tm.white, 48 * S, 10 * S) + 8 * S

  -- their fuel, in their colour (same bar as their leaderboard plate)
  local frac = math.max(0, math.min(1, p.fuel / p.fuelMax))
  local gw, gh = 360 * S, 10 * S
  tm.gauge(vec2(cx - (gw + gh * tm.SKEW) / 2, y), gw, gh, frac, tm.playerColor(s.current))
  y = tm.centerChip(cx, y + gh + 6 * S, 'FUEL ' .. fmt.fuel(p.fuel), 18 * S, tm.panelDeep, tm.fuelColor(frac)) + 14 * S

  if s.mode == game.MODE_ELIMINATION then
    local above = game.playerAbove(s.current)
    if above then
      local t = s.players[above]
      y = tm.centerChip(cx, y, 'BEAT ' .. up(t.nick) .. '  ' .. fmt.clock(t.best), 26 * S, tm.panel, tm.gold) + 4 * S
      y = tm.centerChip(cx, y, 'OR RUN DRY AND YOU ARE OUT', 13 * S, tm.panelDeep, tm.dim) + 4 * S
    end
  else
    y = tm.centerChip(cx, y, 'SET ONE VALID LAP', 24 * S, tm.panel, tm.gold) + 4 * S
  end

  local last = s.lastLap
  if last then
    local text = up(last.nick) .. ' ' .. fmt.clock(last.time)
    if last.delta and last.vsNick then text = text .. '   ' .. fmt.delta(last.delta) .. ' VS ' .. up(last.vsNick) end
    local bg = tm.panelDeep
    if last.delta then bg = last.delta < 0 and tm.ahead or tm.behind end
    y = tm.centerChip(cx, y + 10 * S, text, 15 * S, bg, tm.white) + 4 * S
  end

  local hint = 'PRESS GO IN THE TM HOTSEAT WINDOW'
  if controls.bound() then hint = 'PRESS YOUR BUTTON TO GO' end
  tm.centerChip(cx, y + 18 * S, hint, 13 * S, tm.alpha(tm.panelDeep, 0.75), tm.dim)
end

local function winnerCard(S, scr)
  local winner = nil
  for _, p in ipairs(game.state.players) do
    if not p.eliminated then winner = p break end
  end
  if winner == nil then return end
  local cx = scr.x / 2
  local y = scr.y * 0.14
  y = tm.centerChip(cx, y, 'WINNER', 26 * S, tm.gold, tm.white) + 8 * S
  y = tm.centerChip(cx, y, up(winner.nick), 64 * S, tm.panel, tm.gold, 40 * S, 10 * S) + 6 * S
  if winner.best then tm.centerChip(cx, y, fmt.clock(winner.best), 24 * S, tm.panelDeep, tm.white) end
end

-- ----------------------------------------------------------------------------

local function draw()
  local s = game.state
  if s.phase == game.PHASE_SETUP or #s.players == 0 then return end
  local scr = screenSize()
  local S = scr.y / 1080 * (settings.hudScale or 1)

  if s.phase == game.PHASE_HANDOVER then
    ui.drawRectFilled(vec2(0, 0), scr, rgbm(0, 0, 0, 0.62))
  end
  leaderboard(S)
  if s.phase == game.PHASE_DRIVING then
    driveHud(S, scr)
  elseif s.phase == game.PHASE_HANDOVER then
    handoverCard(S, scr)
  elseif s.phase == game.PHASE_OVER then
    winnerCard(S, scr)
  end
end

function M.draw()
  if not settings.hudOverlay then return end
  local ok, err = pcall(draw)
  M.lastError = (not ok) and tostring(err) or nil
end

return M
