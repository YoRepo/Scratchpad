# Scratchpad Side-Scroller: notes for Claude sessions

A medieval 2D side-scrolling RPG in the spirit of MapleStory, built with **Godot 4.7.2** and played in
the browser through GitHub Pages. You play a knight; the world and its creatures are inspired by
Romanesque illumination marginalia. The owner tests on an **Android phone in a mobile browser**, so
touch controls must keep working. Sessions do not share memory: read this file first.

## Non-negotiables

- **One home per concern.** Every feature has a single source of truth (listed below). Adding,
  replacing or removing a feature must not require hunting for fragments across the project.
- **Nothing reads `Input` except `PlayerInput` and UI widgets.** Gameplay consumes a `PlayerIntent`.
- **Behaviour lives in states, numbers live in resources, text lives in content.** The player's
  states decide; `PlayerMovementConfig` tunes; `content/` holds levels and dialogue.
- **Systems talk through `GameEvents` when they must stay decoupled** (UI listening to gameplay).
  Two nodes that can reasonably reference each other should do so directly instead.
- **Every push that touches `game/` passes `gdlint`, the headless engine test and the browser
  smoke test.** CI runs all three before deploying; run them locally first.
- Agree big design choices (art style, combat model, map structure, progression) with the owner
  before building them. Small engineering calls are yours.

## Where things are

| Path | Owns |
| --- | --- |
| `game/src/core/input_actions.gd` | Action names and default key bindings (autoload `InputActions`). |
| `game/src/core/collision_layers.gd` | Physics layer numbers, mirrored from `[layer_names]` in `project.godot`. |
| `game/src/core/game_events.gd` | The global signal bus (autoload `GameEvents`). |
| `game/src/core/device_info.gd` | Touch detection (autoload `DeviceInfo`). |
| `game/src/core/debug_bridge.gd` | `window.__game` state for browser tests (autoload `DebugBridge`); systems register providers. |
| `game/src/player/player.gd` + `player.tscn` | The knight's body: physics helpers, components, collision setup. |
| `game/src/player/states/*.gd` | Behaviour: Idle, Run, Air, Crouch, Climb, Attack, Talk. `PlayerState` holds shared transitions. |
| `game/src/player/player_input.gd`, `player_intent.gd` | Input reading and the per-frame intent. |
| `game/content/config/player_movement.tres` | Movement feel (`PlayerMovementConfig`). |
| `game/src/player/climb_detector.gd`, `interactor.gd`, `hitbox.gd` | Player components for climbables, interactables, attacks. |
| `game/src/player/player_visual.gd` | What the knight looks like (placeholder rectangles today). |
| `game/src/world/foothold.gd` | Walkable geometry from a polygon: platforms, walls, hills. `one_way` makes it jump-through. |
| `game/src/world/climbable.gd` | Ladders and ropes (`kind`, `length`, `exit_top`). |
| `game/src/world/interactable.gd`, `portal.gd`, `npc/npc.gd` | Things the knight can act on; portals change level, NPCs talk. |
| `game/src/world/health.gd`, `hurtbox.gd`, `hit_info.gd`, `training_dummy.gd` | Receiving side of combat. |
| `game/src/world/level.gd` | A map's root: `display_name`, `bounds`, spawns, landmarks for tests. |
| `game/src/world/game_camera.gd` | Camera framing, smoothing, bounds. |
| `game/src/game/game.gd` + `game.tscn` | Main scene: owns the player, camera, HUD, touch controls; loads levels. |
| `game/src/dialogue/*` | `DialogueData` (resource, with optional end choices), `DialogueRunner` (autoload), nothing else knows dialogue internals. |
| `game/src/animation/*` | `SpriteSheetLoader` (reads a character folder's sheets) and `CharacterVisual` (plays them; origin = feet). |
| `game/src/items/*` | `ItemData` + `ItemCatalog` (autoload), `Inventory` (autoload), `DropTable`, `Pickup`, `DropSpawner`. |
| `game/src/mobs/*` | `MobConfig` (resource), `Mob` body, creature states (idle, wander, chase, attack, hurt, dead). |
| `game/src/quests/*` | `QuestData` (resource) and `QuestLog` (autoload); NPCs ask it which conversation stage to run. |
| `game/src/world/prop.gd`, `parallax_backdrop.gd`, `ground_strip.gd` | Painted scenery: props from `assets/props/props.json`, parallax layers and ground strips from `assets/backdrops`. |
| `game/content/items`, `mobs`, `quests`, `dialogue` | Data: every item, creature kind, quest and conversation. |
| `game/assets/characters|creatures|npcs/<name>/` | Animation sheets + `character.json` produced by the art pipeline (`tools/art/CONVENTIONS.md`). |
| `game/src/ui/hud.gd`, `dialogue_box.gd`, `touch_controls.gd` | HUD, dialogue UI, on-screen buttons (built from a table in code). |
| `game/content/levels/<name>/<name>.tscn` | Maps: `town` (the game) and `meadow` (the test level the browser tour uses via `?level=meadow`). |
| `game/tests/headless_smoke.tscn` | In-engine integration test. `tools/web_smoke_test.js` is the browser test. |

## Engine rules the game depends on

- Web export keeps `variant/thread_support=false` (GitHub Pages sends no cross-origin isolation headers).
- `editor/export/convert_text_resources_to_binary=false` stays off: the export-time conversion
  dropped `PackedStringArray` exports from script resources (seen in 4.7.2 with dialogue `.tres`).
- Renderer `gl_compatibility`; base viewport 640x360; stretch `canvas_items` + `expand`; nearest filtering.
- Physics layers: 1 world_solid, 2 world_platform (one-way), 3 climbable, 4 interactable, 5 player, 6 hurtbox.
- Player collision: `floor_constant_speed`, `floor_snap_length 6`, `floor_max_angle 50°` make slopes work.
- Climb rules: Up grabs a climbable the body overlaps; Down at a climbable's top grabs it downward;
  Jump + Left/Right jumps off; reaching the top steps onto the foothold when `exit_top` is true.
- Down on a foothold crouches; Down+Jump drops through one-way footholds (the `FootholdProbe` ray decides).
- Up doubles as "interact" (MapleStory convention) with E and Enter as alternatives.
- `window.__game` fields the tests rely on: `booted, version, touch, viewport, buttons, level, landmarks,
  x, y, vx, vy, on_floor, facing, state, attacking, jumps, attacks, interactable, presses,
  interactions, interaction_result, dialogue_active, dialogue_index, dialogue_total, dialogue_last_start`.
  Extend; do not remove or rename.
- Commit generated sidecars (`*.import`, `*.gd.uid`). Never commit `game/.godot/`, `build/`, `tools/node_modules/`.
- The workflow stamps `config/version` with the commit hash; the HUD shows it.

## Working in a cloud session

Godot is not preinstalled. Fetch it into the session scratchpad directory (not `/tmp`, not the repo):

```sh
V=4.7.2
BASE="https://github.com/godotengine/godot/releases/download/${V}-stable"
curl -fsSL -o godot.zip "$BASE/Godot_v${V}-stable_linux.x86_64.zip" && unzip -q godot.zip
curl -fsSL -o templates.tpz "$BASE/Godot_v${V}-stable_export_templates.tpz"   # about 1.3 GB
T="$HOME/.local/share/godot/export_templates/${V}.stable"; mkdir -p "$T"
unzip -q -j templates.tpz templates/version.txt templates/web_nothreads_release.zip templates/web_nothreads_debug.zip -d "$T"
pip install "gdtoolkit==4.*"
```

Then, from the repo root, with `GODOT` pointing at the extracted binary:

```sh
gdlint game/src game/tests
$GODOT --headless --path game --import
$GODOT --headless --path game tests/headless_smoke.tscn        # in-engine checks, a few seconds
$GODOT --headless --path game --export-release "Web" "$PWD/build/web/index.html"
node tools/web_smoke_test.js build/web build/smoke             # Playwright + Chromium are preinstalled
```

Look at the screenshots the browser test writes. The `github.io` host is blocked from cloud sessions,
so verify the hosted build through the Actions run and the owner's phone, not by fetching the page.
Each session works on its own `claude/**` branch and the workflow deploys whatever was pushed last.
If the deploy job is rejected by environment protection, the `github-pages` environment (repo Settings,
Environments) needs its deployment-branch rule to allow `claude/*`; only the owner can change that.

## Art and AI tools

- `GEMINI_API_KEY` is set in the environment for image generation (concept art, backdrops, portraits,
  icons). Send it in the `x-goog-api-key` header. Never commit or print it: the repo is public.
  Image models available as of October 2026: `gemini-3-pro-image`, `gemini-3.1-flash-image`,
  `gemini-3.1-flash-lite-image`, `gemini-2.5-flash-image`; video: `veo-3.1-*`. Confirm cost with the
  owner before bulk generation; keep generated sources out of git unless they are final assets.
- No art pipeline exists yet; visuals are placeholder rectangles and `_draw()` shapes. Animated sprites
  need frame-to-frame consistency that image models handle poorly: plan that pipeline with the owner.

## Design direction so far

- Feel: MapleStory. Fixed-height jumps (`jump_velocity -430`, `gravity 1100`, `run_speed 150`),
  one-way footholds, ladders and ropes, crouch, slopes, a short sword swing (10 damage).
- Setting: medieval; a knight; marginalia creatures (first one: a giant snail training dummy).
- Maps: `meadow` (test level with every feature) and `cloister` (tiny second map) linked by portals.
- Art: smooth oil-painted Romanesque marginalia; characters are Veo clips from one base frame (see tools/art/CONVENTIONS.md).
- Done: the knight's painted animations, creatures with contact damage and loot, inventory, the Torn Psalter quest, the town map.
- Not started: skills, shops, save games, more maps. Discuss each with the owner before building.
