#!/usr/bin/env python3
"""Turn a green-screen clip into keyed sprite frames plus review material.

    python3 tools/art/frames.py clip.mp4 out_dir [--fps 12] [--start 0] [--end 0] [--tolerance 90]
                                [--height 0] [--name walk]

Extracts frames with ffmpeg, keys the green, finds one bounding box that covers every frame
(so the sprite does not jitter), writes out_dir/<name>_NN.png, out_dir/<name>.json (frame count,
size, fps), out_dir/<name>_sheet.png (a strip of all frames) and out_dir/<name>_preview.gif.
"""
import argparse
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from cutout import despill, key_alpha  # noqa: E402


def remove_specks(alpha: np.ndarray, min_blob: int) -> np.ndarray:
    """Clear small isolated blobs (key noise) so they cannot inflate the bounding box."""
    from scipy import ndimage
    labels, count = ndimage.label(alpha > 24)
    if count == 0:
        return alpha
    sizes = ndimage.sum(np.ones_like(alpha, dtype=np.int32), labels, index=np.arange(1, count + 1))
    small = np.isin(labels, np.where(sizes < min_blob)[0] + 1)
    cleaned = alpha.copy()
    cleaned[small] = 0
    return cleaned


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("clip")
    parser.add_argument("out_dir")
    parser.add_argument("--fps", type=float, default=12.0)
    parser.add_argument("--start", type=float, default=0.0, help="seconds")
    parser.add_argument("--end", type=float, default=0.0, help="seconds (0 = clip end)")
    parser.add_argument("--tolerance", type=float, default=90.0)
    parser.add_argument("--height", type=int, default=0, help="resize frames to this height (0 = keep)")
    parser.add_argument("--scale", type=float, default=0.0, help="resize frames by this factor (shared by all clips of a character)")
    parser.add_argument("--crop", default="", help="fixed source crop x0,y0,x1,y1 (default: tight box over all frames)")
    parser.add_argument("--origin", default="640,660", help="source x,y of the character origin: horizontal centre, ground line")
    parser.add_argument("--min-blob", type=int, default=400, help="drop keyed blobs smaller than this many pixels")
    parser.add_argument("--name", default="anim")
    args = parser.parse_args()

    out = pathlib.Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        command = ["ffmpeg", "-loglevel", "error", "-y", "-ss", str(args.start), "-i", args.clip]
        if args.end > 0:
            command += ["-to", str(args.end - args.start)]
        command += ["-vf", f"fps={args.fps}", f"{tmp}/f_%04d.png"]
        subprocess.run(command, check=True)
        raw = sorted(pathlib.Path(tmp).glob("f_*.png"))
        if not raw:
            sys.exit("no frames extracted")
        keyed = []
        for path in raw:
            pixels = np.array(Image.open(path).convert("RGBA"))
            pixels[:, :, 3] = key_alpha(pixels[:, :, :3], (0, 255, 0), args.tolerance)
            pixels = despill(pixels, (0, 255, 0))
            pixels[:, :, 3] = remove_specks(pixels[:, :, 3], args.min_blob)
            keyed.append(pixels)
    if args.crop:
        box = tuple(int(v) for v in args.crop.split(","))
    else:
        alpha_any = np.zeros(keyed[0].shape[:2], dtype=bool)
        for pixels in keyed:
            alpha_any |= pixels[:, :, 3] > 24
        rows = np.where(alpha_any.any(axis=1))[0]
        cols = np.where(alpha_any.any(axis=0))[0]
        box = (int(cols[0]), int(rows[0]), int(cols[-1]) + 1, int(rows[-1]) + 1)
    frames = []
    for pixels in keyed:
        frame = Image.fromarray(pixels, "RGBA").crop(box)
        if args.scale > 0:
            frame = frame.resize((max(1, round(frame.width * args.scale)), max(1, round(frame.height * args.scale))), Image.LANCZOS)
        elif args.height > 0:
            frame = frame.resize((max(1, int(frame.width * args.height / frame.height)), args.height), Image.LANCZOS)
        frames.append(frame)
    ox, oy = (float(v) for v in args.origin.split(","))
    factor = frames[0].height / (box[3] - box[1])
    origin = [round((ox - box[0]) * factor, 2), round((oy - box[1]) * factor, 2)]
    for index, frame in enumerate(frames):
        frame.save(out / f"{args.name}_{index:02d}.png")
    width, height = frames[0].size
    columns = min(len(frames), 12)
    rows_count = (len(frames) + columns - 1) // columns
    sheet = Image.new("RGBA", (width * columns, height * rows_count), (90, 110, 90, 255))
    for index, frame in enumerate(frames):
        sheet.alpha_composite(frame, ((index % columns) * width, (index // columns) * height))
    sheet.save(out / f"{args.name}_sheet.png")
    preview = [Image.alpha_composite(Image.new("RGBA", frame.size, (90, 110, 90, 255)), frame).convert("P") for frame in frames]
    preview[0].save(out / f"{args.name}_preview.gif", save_all=True, append_images=preview[1:],
                    duration=int(1000 / args.fps), loop=0, disposal=2)
    (out / f"{args.name}.json").write_text(json.dumps({
        "name": args.name, "frames": len(frames), "width": width, "height": height, "fps": args.fps,
        "columns": columns, "source_box": list(box), "origin": origin, "factor": round(factor, 5),
    }, indent=1))
    print(f"{len(frames)} frames {width}x{height} -> {out}/{args.name}_NN.png, sheet, preview gif; box={box}")


if __name__ == "__main__":
    main()
