# VOID RUNNER: Dimension Shift

A hardcore infinite runner game where you phase between **3 parallel dimensions** to survive.

## Concept

Every obstacle exists in up to two dimensions — deadly in those, a passthrough in its **safe dimension**. You must read the environment, shift dimensions at the right moment, chain combos, and outlast the ever-accelerating void.

## Dimensions

| # | Name | Visual Style | Colors |
|---|------|-------------|--------|
| 0 | **CYBER** | Neon city, perspective grid | Pink / Cyan |
| 1 | **VOID** | Cosmic ruins, floating runes | Purple / Gold |
| 2 | **FLUX** | Matrix rain, circuit floor | Green / White |

## Controls

| Action | Mobile | Keyboard |
|--------|--------|----------|
| Jump / Double Jump | Tap left side or swipe UP | `↑` `Space` `W` |
| Shift dimension → | Swipe RIGHT | `→` `D` |
| Shift dimension ← | Swipe LEFT | `←` `A` |
| Void Dash (invincibility burst) | Double-tap | `↓` `S` |
| Pause | Tap pause icon | `P` `Esc` |

## Mechanics

- **Dimension Shift** — Tap/swipe left or right to cycle through dimensions. Obstacles harmless in your current dimension are shown faded; deadly ones glow menacingly.
- **Combo Multiplier** — Each shift within a time window builds your combo and score multiplier (up to ×3.0).
- **Void Dash** — Grants brief invincibility + visual burst. 3 charges that recharge over time. Shows in the HUD.
- **Portals** — Floating rings award bonus score and auto-shift your dimension.
- **Safe Dim Hint** — The bottom bar shows which dimension to shift to when a deadly obstacle is ahead.
- **Procedural Difficulty** — Speed and obstacle complexity scale smoothly from score 0 → 3000.

## Running Locally

```bash
cd VoidRunner
python3 -m http.server 8080
# Open http://localhost:8080
```

No build step — pure HTML5 + ES Modules.

## Architecture

```
VoidRunner/
├── index.html          Main entry point + module loader
├── css/style.css       All styles + animations
└── src/
    ├── engine.js       Game loop, state machine, input
    ├── world.js        3-dimension background renderers + parallax
    ├── player.js       Player physics, jump, dash, draw
    ├── obstacles.js    Procedural generation + collision
    ├── particles.js    Pooled particle system
    ├── audio.js        Web Audio API synth engine (no files needed)
    └── ui.js           DOM HUD & screen management
```
