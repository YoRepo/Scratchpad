# Art production conventions

Everything visual in the game is generated with `tools/art/gen.py`, cut out, and (for characters)
split into puppet parts. Follow this file exactly: the runtime and the tests depend on it.

## Style and pose

- Style is fixed by `tools/art/style.txt`, which `gen.py` prepends to every prompt. Do not restate
  or contradict it; add only the subject.
- Characters and creatures: **strict side profile facing the viewer's right**, head facing the same
  way as the body, limbs held clear of the torso, feet apart, nothing in the hands. Generate one
  **reference** image first (whole figure, green backdrop), then every parts sheet with `--ref` on
  that reference so the pieces match it.
- **Backdrop**: a flat solid bright pure green (#00FF00) screen, stated in every prompt
  ("flat solid bright pure green (#00FF00) background, no texture, no vignette, no shadows, no text,
  no labels, nothing else"). Never parchment, never white. `split.py` and `cutout.py` key on green.
- **At most four pieces per sheet**, laid out in one row with wide empty gaps, each piece complete
  and not touching another. More pieces than that and the model stops following the layout.
- Ask for pieces "at the same scale as the reference". Pieces are later scaled by one number per
  character, so relative sizes must be right on the sheet.

## Tools

```sh
python3 tools/art/gen.py --tag <family> --tag-cap <usd> --prompt "..." --out <png> [--ref ref.png] [--aspect 1:1|16:9|9:16|4:3] [--size 1K|2K]
python3 tools/art/split.py sheet.png out_dir/       # key on green, split into piece_NN.png + contact.png + pieces.json
python3 tools/art/cutout.py in.png out.png           # key on green, trim; --mode rembg for images with no flat backdrop
python3 tools/art/assemble.py puppet.json preview.png  # render a rig at rest pose (red dots = pivots, blue = ground)
```

- Model: `gemini-3.1-flash-image` for everything; `gemini-3-pro-image` only for a final hero
  reference or a backdrop that flash keeps getting wrong. Size `1K` for pieces and props,
  `2K` for backdrops.
- Every call costs money and is logged to `tools/art/ledger.csv`. Stay under your family's
  `--tag-cap`; the tool refuses once it is reached. Do not retry blindly: change the prompt.
- Look at every result with the image viewer before accepting it. Reject and regenerate when:
  wrong view or facing, overlapping or touching pieces, a missing or extra piece, text or labels,
  a cut-off edge, a non-green backdrop, a piece that does not match the reference, or a style
  drift (outlines, pixel look, photorealism).

## Folders

```
game/assets/characters/<name>/   reference.png (keyed), parts/*.png, puppet.json
game/assets/creatures/<name>/    same layout; name = snail | hare | hedgehog
game/assets/npcs/<name>/         same layout; a lighter rig (see below)
game/assets/backdrops/           sky.png and keyed parallax layers
game/assets/props/               keyed props + props.json
game/assets/items/               keyed 1:1 icons
game/assets/ui/                  keyed UI pieces
```
Source sheets and contact sheets go to your scratchpad directory, not the repo. Only keyed,
trimmed PNGs and manifests are committed. Keep each committed PNG under 1.5 MB.

## World scale

The game viewport is 640x360 world pixels. Target heights in world pixels:

| Thing | Height |
| --- | --- |
| Knight (hero) | 84 |
| NPC adult | 80 to 88 |
| Snail | 40 (about 64 wide) |
| Hare | 46 |
| Hedgehog | 32 |
| Church | 270; inn 210; house 150; gate arch 140; market stall 80; well 60 |
| Tree | 170 to 230; bush 40; fence 40 |
| Item icon | 22 |

`scale` in a manifest is world pixels per sheet pixel: `target_height / figure_height_in_sheet_px`.

## Character animation: base frame, clips, frames

Characters are animated as frame sequences generated with Veo from one **base frame**, never as
rotated puppet parts (dangling cloth needs real frames). Recipe:

1. Generate the character reference (strict side profile, green) with `gen.py`; cut it out with
   `cutout.py --mode rembg` if the backdrop came out non-green.
2. Build the base canvas: a 1280x720 flat green image (#00FF00) with the figure placed so its feet
   sit on y = 660 and its horizontal centre at x = 640; standing height 560 px for a human-sized
   figure (scale creatures to their world size relative to that: hero 84 world px = 560 canvas px,
   so a 40 px snail is about 267 canvas px tall). Save it as `base.png` in the scratch folder.
3. For each animation run `video.py` with `--first base.png` (and `--last base.png` for loops and
   for actions that return to standing; omit it for death). Model `veo-3.1-fast-generate-preview`
   for the hero and NPCs, `veo-3.1-lite-generate-preview` for creatures unless Lite fails. 8 s for
   loops, 4 to 6 s for one-shot actions. Prompt: "2D animated game sprite of the painted <X> from
   the image, side view facing right at all times, same painted manuscript style, same size,
   staying centered in frame. The camera is locked off: no camera movement, no zoom, no pan. The
   background stays a flat solid bright green screen the whole time: no ground shadow, no other
   objects, no text, no watermark, no extra characters, no 3D or photorealistic look." followed by
   the action, "in place", and "The last frame returns to the exact starting pose." for loops.
   Veo 3.1 does not accept negativePrompt; fold negatives into the prompt.
4. `frames.py clip.mp4 frames/ --fps 24 --scale 0.4 --origin 640,660 --name <anim>` keys the
   green and writes 24 fps frames at a fixed 0.4 scale so every clip of a character shares one
   scale (use the same `--scale` for all of a character's clips).
5. `cycle.py frames/<anim>.json game/assets/characters/<name>/anim --mode loop|once --fps 12`
   picks one period (loop) or the motion segment (once), resamples to 12 fps, and writes
   `<anim>.png` (sheet) + `<anim>.json` (frames, columns, size, fps, loop, origin). Look at
   `<anim>_preview.gif` or the sheet and reject clips with drift, a changed costume, or a
   backdrop that is not keyable.
6. Add the animation to `game/assets/characters/<name>/character.json`:
   `{"world_height": 84, "source_height": 560, "frame_scale": 0.4, "animations": ["idle", "walk", ...]}`.
   `SpriteSheetLoader` reads this at runtime.

Required animations: hero idle, walk, jump (once: takeoff, air, landing), attack (once), climb
(loop), crouch (once, held on its last frames), hurt (once), die (once, stays on the last frame).
Creatures: idle, move, hurt, die (plus attack for the hare and hedgehog). NPCs: idle, talk.

## Props and layers

- Props: one keyed PNG each, drawn in side view at ground level, `props.json` entry
  `{"name": {"file": "name.png", "height": <world px>, "ground_inset": <px from the image bottom to the ground contact line, in image px>}}`.
- Parallax layers: 16:9, `2K`, generated on green with "nothing drawn above the skyline" so the top
  is transparent after keying. `sky.png` is the one opaque layer (no green).
- Ground strips: wide (16:9, 2K) with the walking surface along a straight horizontal line at a
  stated fraction of the height, keyed above that line. Say "the design must continue off both
  the left and right edges" so a mirrored copy tiles acceptably.

## Budget and reporting

Use your family's tag and cap on every `gen.py` call. When finished, write a short report:
what was produced (paths), what was rejected and why, the ledger total for your tag, and anything
the integrator must know (odd pivots, a missing piece you could not get, a prop that needs flipping).
