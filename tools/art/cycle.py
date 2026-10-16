#!/usr/bin/env python3
"""Pick the usable frames out of an extracted clip and write a game-ready animation.

    python3 tools/art/cycle.py frames_dir/name.json out_dir --mode loop|once [--fps 12] [--max-frames 16]
                               [--base base_frame.png]

loop: finds the clip's repeat period by comparing frames, takes one period starting at the frame
closest to the first frame, and resamples it to --fps. once: keeps the frames from the first visible
motion until the pose settles back (or the clip ends), resampled to --fps. Writes out_dir/<name>.png
(a sheet, 12 columns) and out_dir/<name>.json for SpriteSheetLoader.
"""
import argparse
import json
import pathlib

import numpy as np
from PIL import Image


def load_frames(meta_path: pathlib.Path):
    meta = json.loads(meta_path.read_text())
    folder = meta_path.parent
    frames = [Image.open(folder / f"{meta['name']}_{i:02d}.png").convert("RGBA") for i in range(meta["frames"])]
    return meta, frames


def small(frame: Image.Image) -> np.ndarray:
    thumb = frame.resize((48, 64), Image.BILINEAR)
    pixels = np.array(thumb).astype(np.float32)
    rgb = pixels[:, :, :3] * (pixels[:, :, 3:4] / 255.0)
    return np.concatenate([rgb.ravel(), pixels[:, :, 3].ravel() * 2.0])


def distance(a: np.ndarray, b: np.ndarray) -> float:
    return float(np.sqrt(((a - b) ** 2).mean()))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("meta")
    parser.add_argument("out_dir")
    parser.add_argument("--mode", default="loop", choices=["loop", "once"])
    parser.add_argument("--fps", type=float, default=12.0)
    parser.add_argument("--max-frames", type=int, default=16)
    parser.add_argument("--min-period", type=float, default=0.4, help="seconds")
    parser.add_argument("--max-period", type=float, default=2.0, help="seconds")
    parser.add_argument("--settle", type=float, default=0.0, help="once: distance below which the pose counts as settled (0 = auto)")
    parser.add_argument("--window", default="", help="only consider frames between these seconds, e.g. 2.5,6.5")
    parser.add_argument("--reverse", action="store_true",
                        help="play the kept frames backwards (a walk whose planted foot slides forward is a moonwalk)")
    parser.add_argument("--stop-at-peak", action="store_true",
                        help="once: end at the frame farthest from the start (a pose that is held, e.g. crouch)")
    args = parser.parse_args()

    meta_path = pathlib.Path(args.meta)
    meta, frames = load_frames(meta_path)
    src_fps = float(meta["fps"])
    if args.window:
        w0, w1 = (float(v) for v in args.window.split(","))
        frames = frames[int(w0 * src_fps): int(w1 * src_fps)]
    sigs = [small(frame) for frame in frames]
    count = len(frames)

    if args.mode == "loop":
        best = None
        lo = max(2, int(args.min_period * src_fps))
        hi = min(count - 2, int(args.max_period * src_fps))
        for period in range(lo, hi + 1):
            score = np.mean([distance(sigs[i], sigs[i + period]) for i in range(0, count - period)])
            if best is None or score < best[0]:
                best = (score, period)
        period = best[1]
        # start at the frame (within the first period) closest to frame 0, so the loop "contains" the base pose
        start = min(range(0, period), key=lambda i: distance(sigs[i], sigs[0]))
        picked_idx = [start + i for i in range(period)]
        info = f"period {period} frames ({period / src_fps:.2f}s), start {start}"
    else:
        diffs = [distance(sigs[0], sig) for sig in sigs]
        noise = np.percentile(diffs[: max(2, int(0.15 * src_fps))], 90) if count > 4 else 0.0
        threshold = args.settle if args.settle > 0 else max(noise * 2.5, 6.0)
        onset = next((i for i, d in enumerate(diffs) if d > threshold), 0)
        peak = int(np.argmax(diffs))
        end = next((i for i in range(peak, count) if diffs[i] < threshold), count - 1)
        if args.stop_at_peak:
            end = peak
        picked_idx = list(range(max(onset - 1, 0), end + 1))
        info = f"onset {onset}, peak {peak}, end {end}, threshold {threshold:.1f}"

    # resample to the requested fps, capped
    want = max(2, min(args.max_frames, int(round(len(picked_idx) * args.fps / src_fps))))
    positions = np.linspace(0, len(picked_idx) - 1, num=want, endpoint=(args.mode == "once"))
    chosen = [picked_idx[int(round(p))] for p in positions]
    if args.reverse:
        chosen.reverse()
    out_frames = [frames[i] for i in chosen]
    width, height = out_frames[0].size
    columns = min(len(out_frames), 12)
    rows = (len(out_frames) + columns - 1) // columns
    sheet = Image.new("RGBA", (width * columns, height * rows), (0, 0, 0, 0))
    for index, frame in enumerate(out_frames):
        sheet.alpha_composite(frame, ((index % columns) * width, (index // columns) * height))
    out = pathlib.Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    name = meta["name"]
    sheet.save(out / f"{name}.png", optimize=True)
    (out / f"{name}.json").write_text(json.dumps({
        "name": name, "frames": len(out_frames), "columns": columns, "width": width, "height": height,
        "fps": args.fps, "loop": args.mode == "loop", "origin": meta.get("origin"), "factor": meta.get("factor"),
        "source_frames": chosen,
    }, indent=1))
    preview = [Image.alpha_composite(Image.new("RGBA", f.size, (90, 110, 90, 255)), f).convert("P") for f in out_frames]
    preview[0].save(out / f"{name}_preview.gif", save_all=True, append_images=preview[1:],
                    duration=int(1000 / args.fps), loop=0, disposal=2)
    print(f"{name}: {info}; kept {len(out_frames)} frames at {args.fps} fps -> {out}/{name}.png")


if __name__ == "__main__":
    main()
