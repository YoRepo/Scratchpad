#!/usr/bin/env python3
"""Cut a jump clip into a phase sheet: frames picked by the game's airborne state.

    python3 tools/art/jump_sheet.py frames/jump.json out_dir [--name jump] [--land-frames 2]

Reads frames.py output of a clip in which the character jumps once on the spot. Tracks the
feet (lowest opaque row) to find lift-off, apex and touchdown, then keeps: "rise" (midway up),
"apex" (highest point), "fall" (midway down) and "land" (the deepest crouch after touchdown,
plus the frames that follow it). Writes <name>.png and <name>.json with a "phases" map, which
SpriteSheetLoader passes to CharacterVisual.show_phase(). Frames are the clip's; the game
decides which one shows from the vertical speed.
"""
import argparse
import json
import pathlib
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from cycle import load_frames  # noqa: E402


def feet_y(frame: Image.Image) -> float:
    alpha = np.array(frame)[:, :, 3]
    rows = np.where((alpha > 100).sum(axis=1) >= 3)[0]
    return float(rows.max()) if len(rows) else float("nan")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("meta")
    parser.add_argument("out_dir")
    parser.add_argument("--name", default="jump")
    parser.add_argument("--land-frames", type=int, default=2)
    parser.add_argument("--lift", type=float, default=6.0, help="px the feet must rise to count as airborne")
    args = parser.parse_args()
    meta, frames = load_frames(pathlib.Path(args.meta))
    feet = np.array([feet_y(f) for f in frames])
    ground = np.nanmedian(feet[: max(3, len(feet) // 10)])
    airborne = np.where(feet < ground - args.lift)[0]
    if len(airborne) == 0:
        sys.exit("no lift-off found: the feet never leave the ground line")
    liftoff, touchdown = int(airborne[0]), int(airborne[-1])
    apex = int(liftoff + np.argmin(feet[liftoff:touchdown + 1]))
    rise = (liftoff + apex) // 2
    fall = (apex + touchdown) // 2
    # landing: the deepest knee bend after touchdown shows as the lowest figure top
    tops = []
    for frame in frames[touchdown:min(len(frames), touchdown + 12)]:
        alpha = np.array(frame)[:, :, 3]
        rows = np.where((alpha > 100).sum(axis=1) >= 3)[0]
        tops.append(rows.min() if len(rows) else 0)
    land = touchdown + 1 + int(np.argmax(tops[1:])) if len(tops) > 1 else touchdown
    land_frames = list(range(land, min(len(frames), land + args.land_frames)))
    chosen = [rise, apex, fall] + land_frames
    phases = {"rise": [0], "apex": [1], "fall": [2], "land": list(range(3, 3 + len(land_frames)))}
    out_frames = [frames[i] for i in chosen]
    width, height = out_frames[0].size
    sheet = Image.new("RGBA", (width * len(out_frames), height), (0, 0, 0, 0))
    for index, frame in enumerate(out_frames):
        sheet.alpha_composite(frame, (index * width, 0))
    out = pathlib.Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    sheet.save(out / f"{args.name}.png", optimize=True)
    (out / f"{args.name}.json").write_text(json.dumps({
        "name": args.name, "frames": len(out_frames), "columns": len(out_frames), "width": width,
        "height": height, "fps": 12.0, "loop": False, "origin": meta.get("origin"),
        "factor": meta.get("factor"), "source_frames": chosen, "phases": phases,
    }, indent=1))
    print(f"{args.name}: ground y {ground:.0f}, lift-off {liftoff}, apex {apex} (feet {feet[apex]:.0f}), "
          f"touchdown {touchdown}, land {land_frames}; kept {chosen} -> {out}/{args.name}.png")


if __name__ == "__main__":
    main()
