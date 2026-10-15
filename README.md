# Scratchpad Side-Scroller

A 2D side-scrolling game in the spirit of MapleStory, built with [Godot 4.7](https://godotengine.org/)
and playable in a phone or desktop browser.

**Play the latest build:** https://yorepo.github.io/Scratchpad/

## Layout

| Path | What it is |
| --- | --- |
| `game/` | The Godot project. Open `game/project.godot` in Godot 4.7.2 to edit it. |
| `game/scenes/` | Scenes: `main.tscn` (level + HUD), `player.tscn`, `touch_controls.tscn`. |
| `game/scripts/` | GDScript: player movement, input setup, touch-control layout. |
| `.github/workflows/deploy-pages.yml` | Exports the web build and deploys it to GitHub Pages on every push. |
| `tools/web_smoke_test.js` | Headless-browser test that boots the web build and drives the player. |

## How a change reaches your phone

1. A commit touching `game/` is pushed.
2. GitHub Actions downloads Godot, exports the **Web** preset (threads disabled, so no special
   hosting headers are needed), and publishes the result to GitHub Pages.
3. Reload the Pages URL. The HUD shows the version with the short commit hash so you can tell
   the new build has landed.

## Controls

- Keyboard: arrows or A/D to move, Space to jump, X to attack, Down + Jump to drop through a platform.
- Touch: on-screen buttons appear automatically on touch devices.

## Local export and test

```sh
godot --headless --path game --import
godot --headless --path game --export-release "Web" "$PWD/build/web/index.html"
node tools/web_smoke_test.js build/web build/smoke
```

The smoke test needs Playwright with Chromium available to Node.
