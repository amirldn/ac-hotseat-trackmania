-- Bindable buttons (keyboard, wheel or gamepad) via CSP's control system, so
-- drivers can restart or start their turn without reaching for the mouse.
-- Bindings live in AC's controls.ini and can be changed from the setup screen.

local M = {}

local function make(id, onPressed)
  local ok, btn = pcall(ac.ControlButton, id)
  if not ok or btn == nil then return nil end
  pcall(function() btn:onPressed(onPressed) end)
  return btn
end

---@param handlers { restart: fun(), ready: fun() }
function M.init(handlers)
  M.restart = make('app.tm_hotseat/Restart lap', handlers.restart)
  M.ready = make('app.tm_hotseat/Ready (start turn)', handlers.ready)
end

---Label + CSP's binding widget (click it, then press a key/wheel button).
function M.drawBinding(label, btn)
  ui.text(label)
  ui.sameLine(130)
  if btn == nil or not pcall(function() btn:control(vec2(ui.availableSpaceX(), 0)) end) then
    ui.text('(not supported on this CSP build)')
  end
end

---Short description of the current binding for on-screen hints.
function M.hint(btn, fallback)
  if btn == nil then return fallback end
  local ok, configured = pcall(function() return btn:configured() end)
  if ok and configured then return 'your bound button' end
  return fallback
end

return M
