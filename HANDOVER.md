# Handover — v0.2.0 review + Trackmania HUD (from a cloud session)

This work was done in a cloud container with **no access to Assetto Corsa**, so it is
covered by headless tests and rendered previews but has **not run in-game yet**. The
first job for a local session is to install it and run through the checklist below.

Branch: `claude/trackmania-hotseat-ac-mod-jpoeo9` (based on
`claude/trackmania-hotseat-assetto-corsa-nhf49u`). Merge it once the in-game check passes.

## What changed

**Bug fixes / robustness** (`src/game.lua`, `src/ghosts.lua`)
- **Out-laps could bank as laps.** If AC resets the lap timer on a teleport, the
  "first line crossing arms a clean lap" gate fired at the spawn point, so the short
  run to the line counted as a lap. Laps must now cover ≥ 60% of the track length;
  teleport jumps don't count as distance (`trackDistance`, `cfg.minLapFraction`).
- **Teleport chain could stall.** `pcall(physics.teleportCarTo, …)` succeeds even if CSP
  ignores the call for apps, so the fallbacks never ran. Each method is now verified
  (the car must jump ≥ 15 m within 12 frames) before moving on; `ac.tryToTeleportToPits`
  was added before the session-restart fallback.
- **Ghosts played back during the out-lap**, keyed off a meaningless lap clock. They now
  wait on the line until the driver crosses it.
- **Fuel wasn't saved mid-turn**, so a crash/app reload refunded a turn's fuel. It's now
  persisted every 5 s while driving.
- Restart clears stale status messages; elimination order is recorded for final places.

**Features**
- Fullscreen **Trackmania HUD** (`src/overlay.lua`, `src/tmui.lua`): slanted top-left
  leaderboard with fuel-draining player plates, bottom-centre lap clock, **checkpoint
  splits** (blue ahead / red behind, vs the time you're chasing), fuel gauge, LAP
  INVALID / LAST CHANCE banners, full-screen handover card and winner card. Scales with
  resolution; *HUD size* setting on top. Toggle off to get the old in-window standings.
- **Bindable controls** (`src/controls.lua`): *Restart lap* and *Ready (GO)* via CSP's
  binding widgets in the setup screen — works with wheel buttons.
- Tests: 45 assertions in `tests/test_game.lua` (out-lap guard, teleport verification,
  splits, periodic save, …) plus `tests/test_panels.lua`; preview tool in `tools/`.

## In-game checklist (riskiest first)

1. **App loads and the overlay draws** top-left with no window chrome. If not, the app
   window shows a "HUD error" line, and the CSP log has details. Untick *Trackmania HUD*
   to confirm the fallback works.
2. **Font and shapes**: is `Segoe UI` Black Italic rendering, and do the slanted slabs
   fill cleanly? (DirectWrite fonts and `ui.pathFillConvex` in the IN_GAME callback.)
3. **Restart**: which teleport method actually works on this CSP build? Watch for the
   chain falling through to a session restart (slow) when a teleport should have worked.
4. **Out-lap guard**: after a restart, does the out-lap get the "Out-lap ignored" message
   (expected if AC resets the timer on teleport), and does the next flying lap count?
   Check a normal lap on a long and a short track is never rejected.
5. **Checkpoint splits**: appear on the second player's attempts once a ghost exists. If
   they never show, `car.splinePosition` may not start at the timing line on that track.
6. **Ghosts** wait at the line during the out-lap, then run with the lap clock.
7. **Bound buttons** work from the wheel, including Ready on the handover screen.
8. **Fuel save**: quit AC mid-turn, relaunch — fuel should not be refunded.
9. **HUD size** looks right at your resolution (1080p = 100%).

## Ideas not done yet

- Pause the sim on the handover screen (`ac.tryToPause`) so the car doesn't roll and the
  next driver can't practise for free. Check whether AC's pause menu covers the overlay.
- Translucent ghosts: `loaded:setTransparent(true)` is best-effort; verify how it looks.
- Bundle a Trackmania-like font in the app folder (`ui.DWriteFont('Name', './fonts')`).
- A 3-2-1 countdown after GO.
- Publish a new release zip: the README's quick install still links the v1.0.0 release,
  which doesn't include this work.
