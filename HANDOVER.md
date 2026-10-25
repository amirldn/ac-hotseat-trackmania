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
- **Restart = session restart.** The teleport chain was removed after in-game testing:
  the hotlap start (deep in the last sector on Anglesey Club) and pits (just past the line)
  left long out-laps, and after a grid teleport AC didn't start timing on the next line
  crossing. GO/Restart now call `ac.tryToRestartSession` (`sendToStart`), same as the
  pause-menu *Restart session*.
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
- **Bindable control** (`src/controls.lua`): one *GO / Restart* button via CSP's binding
  widget in the setup screen — GO on handover, restart while driving; works with wheel
  buttons. With it bound and the HUD on, the app window hides itself while driving.
- Tests: 45 assertions in `tests/test_game.lua` (out-lap guard, session restart,
  splits, periodic save, …) plus `tests/test_panels.lua`; preview tool in `tools/`.

## In-game checklist (riskiest first)

1. **App loads and the overlay draws** top-left with no window chrome. If not, the app
   window shows a "HUD error" line, and the CSP log has details. Untick *Trackmania HUD*
   to confirm the fallback works.
2. **Font and shapes**: is `Segoe UI` Black Italic rendering, and do the slanted slabs
   fill cleanly? (DirectWrite fonts and `ui.pathFillConvex` in the IN_GAME callback.)
3. **Restart**: GO/Restart restart the session (grid, just behind the line) and the
   clock starts at the line. Check fuel/turn state survives the session restart.
4. **Out-lap guard**: after a restart, does the out-lap get the "Out-lap ignored" message
   (expected if AC resets the timer on teleport), and does the next flying lap count?
   Check a normal lap on a long and a short track is never rejected.
5. **Checkpoint splits**: appear on the second player's attempts once a ghost exists. If
   they never show, `car.splinePosition` may not start at the timing line on that track.
6. **Ghosts** wait at the line during the out-lap, then run with the lap clock.
7. **Bound button** works from the wheel: GO on the handover screen, restart while
   driving; the app window hides while driving and reopens between turns.
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
