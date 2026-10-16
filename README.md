# Scratchpad Side-Scroller

A medieval 2D side-scrolling RPG in the spirit of MapleStory, built with [Godot 4.7](https://godotengine.org/)
and playable in a phone or desktop browser. You play a knight in a world drawn from Romanesque
illumination marginalia.

**Play the latest build:** https://yorepo.github.io/Scratchpad/

## What works today

- Running, fixed-height jumps, slopes, one-way platforms, Down+Jump to drop through them.
- Ladders and ropes: grab with Up, climb down from the top with Down, jump off sideways.
- Crouching, with a headroom check before standing.
- Talking to NPCs; dialogue text lives in resources, not code.
- A sword swing with a hit window, and a training dummy that takes damage.
- Portals between two maps.
- On-screen touch controls on phones, keyboard on desktop.

## Layout

| Path | What it is |
| --- | --- |
| `game/` | The Godot project. Open `game/project.godot` in Godot 4.7.2 to edit it. |
| `game/src/` | Code and reusable scenes, grouped by concern: `core`, `player`, `world`, `npc`, `dialogue`, `ui`, `game`. |
| `game/content/` | Data: levels, dialogue, the movement tuning resource. |
| `game/tests/` | The headless in-engine test scene. |
| `tools/web_smoke_test.js` | Browser test that boots the exported build and plays through every feature. |
| `.github/workflows/deploy-pages.yml` | Lints, tests, exports, and deploys to GitHub Pages on every push. |
| `CLAUDE.md` | Architecture rules and working notes for Claude sessions (worth reading for humans too). |

## Controls

- Keyboard: arrows or A/D to move, Space to jump, X to attack, Down to crouch, Down+Jump to drop
  through a platform, Up to climb or to talk to whoever is in front of you (E and Enter also talk).
- Touch: a d-pad on the left, Jump and Attack on the right, and a context button that appears next
  to things you can talk to or enter.

## How a change reaches your phone

1. A commit touching `game/` or `tools/` is pushed.
2. GitHub Actions lints the GDScript, runs the headless engine test, exports the **Web** preset,
   runs the browser smoke test against that export, and publishes it to GitHub Pages.
3. Reload the Pages URL. The HUD shows the version with the short commit hash.

## Local checks

```sh
gdlint game/src game/tests
godot --headless --path game --import
godot --headless --path game tests/headless_smoke.tscn
godot --headless --path game --export-release "Web" "$PWD/build/web/index.html"
node tools/web_smoke_test.js build/web build/smoke
```

The browser test needs Node with Playwright and Chromium (`cd tools && npm install && npx playwright install chromium`).
