# TM Hotseat — Trackmania-style hotseat mode for Assetto Corsa

Play hotlap battles with friends on **one PC**, Trackmania Hotseat style. Everyone gets a
random nickname, takes turns setting laps on a shared "fuel" budget, and once everyone has
a time it turns into elimination: the slowest player drives and must beat the player above
them before their fuel runs out.

Built as a **CSP Lua app** (requires [Custom Shaders Patch](https://acstuff.club/patch/)).

## How it plays

1. **Setup** — pick the number of players (2–8), a nickname category (Animals, Fruit & Veg,
   Space, Workshop, Mythical) and the fuel budget. Everyone is assigned a random unique noun
   as their nickname. The default fuel budget scales with track length (longer track = more
   fuel) and can be tweaked in 30-second steps.
2. **Opening round** — players drive one at a time in a shuffled order. Your **fuel is a
   personal time budget**: it drains for every second of your turn and is *not* the car's
   real fuel tank. Press **Restart Lap** (button in the app window, or `R` while the window
   is focused) to teleport back to the line at any time — your fuel keeps draining, just
   like Trackmania. As soon as you complete one **valid** lap (track cuts void the lap),
   your fuel drain pauses and the wheel passes to the next player.
3. **Elimination** — once everyone has a time, the **worst-ranked player drives** and must
   beat the time of the player directly above them. Beat it and the wheel passes to the
   player you just demoted (they're last now). Last player standing wins.
4. **Last chance (overtime)** — running out of fuel doesn't end your turn on the spot: you
   get a **last-chance lap** to finish the one you're on. Set a valid lap and you survive;
   **restart while out of fuel and you forfeit** — the wheel passes on (and in elimination
   that means you're out). An amber banner shows while you're in overtime.
5. **Ghosts** — while driving you see up to two ghosts replaying in real time against your
   lap clock: 👑 the overall leader's best lap and ▲ the best lap of the player directly
   above you. Ghosts are visual only (no collisions).

Sound cues play a **low buzz** when you void a lap (cut) and a **bright chime** when the
wheel passes to the next player.

The app window (dock it top-left) always shows every player's fuel bar, best lap and
live standings, plus the target time you need to beat.

## Installation

1. Install [Content Manager](https://acstuff.club/app/) and **Custom Shaders Patch 0.1.79
   or newer** (0.2.x recommended).
2. Copy the `apps/lua/tm_hotseat` folder from this repo into your game folder so you end up
   with:
   ```
   ...\SteamApps\common\assettocorsa\apps\lua\tm_hotseat\manifest.ini
   ```
3. Start any **single-player Practice or Hotlap session** (one car, any track).
4. In-game, open the right-side apps taskbar and enable **TM Hotseat**. Drag the window to
   the top-left corner.

## Notes & troubleshooting

- **Restart/teleport**: the Restart button tries CSP's teleport (hotlap start → grid →
  pits). If your CSP build/session doesn't allow teleporting, it falls back to restarting
  the session — the app keeps all scores, fuel levels and turn order across the restart
  (state is also persisted via `ac.storage`, so it survives an app reload; ghost
  recordings live in memory only and are lost on a full AC restart).
- **Lap validity**: a lap is void if more than 2 wheels leave the track (with a short
  grace period for kerb hops), or if you teleported mid-lap. Set AC's own penalties off —
  the app does its own checking.
- **Ghost model**: ghosts load your car's KN5 (preferring a lighter LOD from `lods.ini`).
  If the model can't be loaded on your build, a marker cross with the player's name is
  drawn at the ghost position instead.
- **One car only**: run the session with just the player car; the app reads car slot 0.

## Repo layout

```
apps/lua/tm_hotseat/
├── manifest.ini        CSP app manifest (window + render callback)
├── tm_hotseat.lua      entry point, wires CSP callbacks
├── src/
│   ├── game.lua        fuel, turns, opening/elimination state machine
│   ├── ghosts.lua      best-lap recording, KN5 ghost playback
│   ├── nicknames.lua   random noun nickname categories
│   ├── panels.lua      setup / handover / driving / results UI
│   └── sound.lua       2D sound cues (cut buzz, next-player chime)
└── sfx/                invalid.wav, next.wav
tests/
└── test_game.lua       headless smoke test of the state machine
```

## Development

The game logic runs headless with the `ac`/`ui` globals stubbed — from the repo root:

```
luajit tests/test_game.lua
```

covers the full flow (opening laps, cut-lap rejection, elimination handovers, fuel-out
elimination, restart persistence, winner detection). All CSP calls that vary between
builds are wrapped in `pcall` with fallbacks.
