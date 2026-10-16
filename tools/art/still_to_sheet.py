#!/usr/bin/env python3
"""Make a one-frame animation sheet from a base canvas (a still standing in for a clip).

    python3 tools/art/still_to_sheet.py base.png out_dir --name idle [--scale 0.4] [--origin 640,660]

Keys the green, crops, scales, and writes out_dir/<name>.png + <name>.json in the same
format cycle.py produces, so SpriteSheetLoader can play it (the runtime adds a breathing
motion to single-frame animations).
"""
import argparse
import json
import pathlib
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from cutout import despill, key_alpha  # noqa: E402
from frames import remove_specks  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("base")
    parser.add_argument("out_dir")
    parser.add_argument("--name", default="idle")
    parser.add_argument("--scale", type=float, default=0.4)
    parser.add_argument("--origin", default="640,660")
    parser.add_argument("--tolerance", type=float, default=90.0)
    args = parser.parse_args()

    pixels = np.array(Image.open(args.base).convert("RGBA"))
    pixels[:, :, 3] = key_alpha(pixels[:, :, :3], (0, 255, 0), args.tolerance)
    pixels = despill(pixels, (0, 255, 0))
    pixels[:, :, 3] = remove_specks(pixels[:, :, 3], 400)
    alpha = pixels[:, :, 3] > 24
    rows = np.where(alpha.any(axis=1))[0]
    cols = np.where(alpha.any(axis=0))[0]
    box = (int(cols[0]), int(rows[0]), int(cols[-1]) + 1, int(rows[-1]) + 1)
    frame = Image.fromarray(pixels, "RGBA").crop(box)
    frame = frame.resize((max(1, round(frame.width * args.scale)), max(1, round(frame.height * args.scale))), Image.LANCZOS)
    ox, oy = (float(v) for v in args.origin.split(","))
    factor = frame.height / (box[3] - box[1])
    out = pathlib.Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    frame.save(out / f"{args.name}.png", optimize=True)
    (out / f"{args.name}.json").write_text(json.dumps({
        "name": args.name, "frames": 1, "columns": 1, "width": frame.width, "height": frame.height,
        "fps": 12.0, "loop": True, "origin": [round((ox - box[0]) * factor, 2), round((oy - box[1]) * factor, 2)],
        "factor": round(factor, 5), "source_frames": [0], "still": True,
    }, indent=1))
    print(f"{args.name}: 1 frame {frame.width}x{frame.height} -> {out}")


if __name__ == "__main__":
    main()
