-- Display settings, persisted between sessions.

return ac.storage({
  hudOverlay = true, -- Trackmania HUD drawn fullscreen; off = classic in-window standings
  hudScale = 1.0,    -- multiplier on top of automatic resolution scaling (1080p = 1.0)
}, 'tm_hotseat_ui')
