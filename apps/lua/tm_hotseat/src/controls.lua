-- One bindable button (keyboard, wheel or gamepad) via CSP's control system, so
-- drivers never reach for the mouse: it means GO on the handover screen and
-- restart while driving. The two phases never overlap, so one button is enough.
-- The binding lives in AC's controls.ini and can be changed from the setup screen.

local M = {}

local function make(id, onPressed)
  local ok, btn = pcall(ac.ControlButton, id)
  if not ok or btn == nil then return nil end
  pcall(function() btn:onPressed(onPressed) end)
  return btn
end

---@param onPressed fun() @Called on every press; the caller decides what it means.
function M.init(onPressed)
  M.action = make('app.tm_hotseat/Ready + restart', onPressed)
end

---Label + CSP's binding widget (click it, then press a key/wheel button).
function M.drawBinding(label, btn)
  ui.text(label)
  ui.sameLine(130)
  if btn == nil or not pcall(function() btn:control(vec2(ui.availableSpaceX(), 0)) end) then
    ui.text('(not supported on this CSP build)')
  end
end

---True if the player has bound the action button to something.
function M.bound()
  if M.action == nil then return false end
  local ok, configured = pcall(function() return M.action:configured() end)
  return ok and configured == true
end

return M
