# Scratchpad Side-Scroller: notes for Claude sessions

MapleStory-inspired 2D side-scroller built with **Godot 4.7.2**, played in the browser through
GitHub Pages. The owner tests on an **Android phone in a mobile browser**, so touch controls must
keep working. Sessions do not share memory: read this file first.

## Where things are

- `game/` is the Godot project (`game/project.godot`). Scenes in `game/scenes/`, scripts in `game/scripts/`.
- `.github/workflows/deploy-pages.yml` exports the Web preset and deploys it to GitHub Pages on every push
  to `main` or any `claude/**` branch that touches `game/`. Build plus deploy takes about a minute.
- `tools/web_smoke_test.js` boots the exported web build in headless Chromium as a touch phone and a
  keyboard desktop, drives the player, and checks the state the game publishes on `window.__game`.
- Live build: https://yorepo.github.io/Scratchpad/ . The HUD shows `v<version>+<commit>` so the owner can
  tell which build they are looking at.

## Working in a cloud session

Godot is not preinstalled. Fetch it into the session scratchpad directory (not `/tmp`, not the repo):

```sh
V=4.7.2
BASE="https://github.com/godotengine/godot/releases/download/${V}-stable"
curl -fsSL -o godot.zip "$BASE/Godot_v${V}-stable_linux.x86_64.zip" && unzip -q godot.zip
curl -fsSL -o templates.tpz "$BASE/Godot_v${V}-stable_export_templates.tpz"   # about 1.3 GB
T="$HOME/.local/share/godot/export_templates/${V}.stable"; mkdir -p "$T"
unzip -q -j templates.tpz templates/version.txt templates/web_nothreads_release.zip templates/web_nothreads_debug.zip -d "$T"
```

Then, from the repo root, with `GODOT` pointing at the extracted binary:

```sh
$GODOT --headless --path game --import
$GODOT --headless --path game --quit-after 120          # runs the main scene headless; script errors show here
$GODOT --headless --path game --export-release "Web" "$PWD/build/web/index.html"
node tools/web_smoke_test.js build/web build/smoke      # Playwright + Chromium are preinstalled in cloud sessions
```

Run the smoke test before every push that touches `game/`, and look at the screenshots it writes.
The `github.io` host is blocked from cloud sessions, so verify the hosted build through the Actions run
and the owner's phone, not by fetching the page.

If the deploy job is rejected with an environment protection error, the `github-pages` environment
(repo Settings, Environments) needs its deployment-branch rule to allow `claude/*`. Only the owner can change that.

## Conventions that must hold

- Web export keeps `variant/thread_support=false` (GitHub Pages sends no cross-origin isolation headers).
- Renderer is `gl_compatibility` (required for web). Base viewport 640x360, stretch mode `canvas_items`,
  aspect `expand`, nearest-neighbour filtering for pixel art.
- Input actions are created in code in `game/scripts/main.gd` (`_setup_input`), not in `project.godot`.
- Touch controls live in `game/scenes/touch_controls.tscn` and are laid out in code from the visible
  viewport. `main.gd` decides visibility with `navigator.maxTouchPoints` on web (Godot's own check is
  wrong in headless browsers).
- On web the game publishes debug state to `window.__game` every 0.25 s. The smoke test depends on the
  fields `booted, version, x, y, vx, vy, on_floor, facing, attacking, jumps, attacks, touch, viewport, buttons`.
  Extend it; do not remove fields.
- Commit generated sidecars (`*.import`, `*.gd.uid`). Never commit `game/.godot/` or `build/`.
- Keep the workflow's version-stamp step working (it rewrites `config/version` in `project.godot`).
- The branch a session is assigned is also the deploy source: whatever was pushed last is what the owner plays.

## Art and AI tools

- `GEMINI_API_KEY` is set in the environment for image generation (concept art, backgrounds, portraits,
  icons). Use the header `x-goog-api-key`. Never commit the key or print it: the repo is public.
  Image models available as of October 2026: `gemini-3-pro-image`, `gemini-3.1-flash-image`,
  `gemini-3.1-flash-lite-image`, `gemini-2.5-flash-image`; video: `veo-3.1-*`. Check pricing before
  bulk generation and keep generated sources out of git unless they are final assets.
- No art pipeline exists yet. Current visuals are `ColorRect` placeholders. Animated character sprites need
  frame-to-frame consistency that image models handle poorly; plan that pipeline with the owner.

## Design direction so far

- Feel: MapleStory. Fixed-height jumps (`JUMP_VELOCITY -430`, `GRAVITY 1100`, `SPEED 150`), one-way
  platforms you jump up through, Down+Jump drops through the platform underfoot, a short attack flash.
- Map is a single 1600x360 test level with seven platforms. Camera is pinned vertically.
- Not started: art style, hero sprite and animations, enemies and combat, ladders and ropes, a real map,
  inventory and skills. Agree big design choices with the owner before building them.
