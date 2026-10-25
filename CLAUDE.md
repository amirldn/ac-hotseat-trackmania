# TM Hotseat — notes for Claude

A Trackmania-style hotseat game mode for Assetto Corsa, built as a **CSP (Custom Shaders
Patch) Lua app**. Players share one PC, take turns setting laps on a per-player "fuel"
time budget, then an elimination round: the slowest drives and must beat the player
above them before their fuel runs out. See `README.md` for the player-facing rules.

## Layout

- `apps/lua/tm_hotseat/` — the app itself; this whole folder is what gets installed.
  - `manifest.ini` — the window section must be the literal `[WINDOW_...]` (CSP syntax,
    not a placeholder — a numbered name made the app disappear in-game).
  - `tm_hotseat.lua` — entry point: CSP callbacks `script.update`, `windowMain`,
    `fullscreenUI` (IN_GAME), `draw3D` (TRANSPARENT).
  - `src/game.lua` — state machine (setup → handover → driving → over), fuel, lap
    validity, teleport chain, checkpoint splits, persistence via `ac.storage`.
  - `src/ghosts.lua` — 20 Hz lap recording (flat arrays, stride 11) and KN5 ghost playback.
  - `src/overlay.lua` + `src/tmui.lua` — fullscreen Trackmania HUD and its drawing kit.
  - `src/panels.lua` — the ImGui app window (setup, GO, restart, classic standings).
- `tests/` — headless LuaJIT tests with CSP globals stubbed.
- `tools/render_hud_preview.lua` — renders the real overlay code to SVG (no game needed).

## Conventions

- **Every CSP call that may vary between builds goes through `pcall` with a fallback.**
  The app must keep working (degraded) on older CSP builds — never let one missing API
  break the game loop. The overlay is wrapped too and reports errors in the app window.
- Don't trust that a CSP call worked just because it didn't throw (e.g. teleports from
  apps can be silently ignored) — verify the effect, as `verifyTeleport` does.
- Match the existing style: 2-space indent, `local M = {}` modules, `---` doc comments on
  public functions, short comments that explain *why*.
- Time formats come from `src/fmt.lua` (`MM:SS.mmm` clock, signed splits).

## Testing

From the repo root (needs `luajit`):

```
luajit tests/test_game.lua
luajit tests/test_panels.lua
```

Both must print `ALL TESTS PASSED`. Add a test for any game-logic change. For HUD work,
render previews with `luajit tools/render_hud_preview.lua <dir>` and convert the SVGs
(e.g. `rsvg-convert`, or open them in a browser). Previews approximate text widths;
real behaviour still needs an in-game check.

## Installing into Assetto Corsa (Windows)

1. Find the AC root: Content Manager → Settings → Assetto Corsa → *AC root folder*, or
   Steam's default `C:\Program Files (x86)\Steam\steamapps\common\assettocorsa`; other
   Steam libraries are listed in `C:\Program Files (x86)\Steam\steamapps\libraryfolders.vdf`.
2. Replace `<AC root>\apps\lua\tm_hotseat` with this repo's `apps\lua\tm_hotseat`
   (remove the old folder first so deleted files don't linger), e.g.
   `robocopy apps\lua\tm_hotseat "<AC root>\apps\lua\tm_hotseat" /MIR`.
   For development, a directory junction avoids the copy step entirely:
   `mklink /J "<AC root>\apps\lua\tm_hotseat" "<repo>\apps\lua\tm_hotseat"`.
3. In AC (single-player Practice or Hotlap, one car), enable **TM Hotseat** from the apps
   taskbar. Lua errors land in `Documents\Assetto Corsa\logs\custom_shaders_patch.log`.
