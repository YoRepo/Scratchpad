#!/usr/bin/env python3
"""Cut a generated image out of its plain backdrop into a trimmed transparent PNG.

    python3 tools/art/cutout.py in.png out.png [--mode rembg|key] [--key-color 255,255,255]
                                [--tolerance 40] [--pad 2] [--no-trim]

key (default) removes pixels near --key-color (green screen) with a soft edge and
de-spills fringes; rembg uses a matting model for images that have no flat backdrop. Prints the trimmed size and the content bounding box.
"""
import argparse
import pathlib

import numpy as np
from PIL import Image


def key_alpha(rgb: np.ndarray, color: tuple, tolerance: float) -> np.ndarray:
    """Alpha from distance to the key colour, with a soft edge band."""
    distance = np.sqrt(((rgb.astype(np.float32) - np.array(color, dtype=np.float32)) ** 2).sum(axis=2))
    alpha = np.clip((distance - tolerance * 0.5) / (tolerance * 0.7), 0.0, 1.0)
    return (alpha * 255).astype(np.uint8)


def despill(pixels: np.ndarray, color: tuple) -> np.ndarray:
    """Pull the key colour out of semi-transparent edge pixels so fringes do not glow."""
    rgb = pixels[:, :, :3].astype(np.float32)
    alpha = pixels[:, :, 3:4].astype(np.float32) / 255.0
    key = np.array(color, dtype=np.float32)
    dominant = int(np.argmax(key))
    others = [i for i in range(3) if i != dominant]
    limit = np.maximum(rgb[:, :, others[0]], rgb[:, :, others[1]])
    channel = rgb[:, :, dominant]
    spill = np.clip(channel - limit, 0, None) * (1.0 - alpha[:, :, 0]) * 0.9
    rgb[:, :, dominant] = channel - spill
    pixels[:, :, :3] = rgb.clip(0, 255).astype(np.uint8)
    return pixels


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("src")
    parser.add_argument("dst")
    parser.add_argument("--mode", default="key", choices=["rembg", "key"])
    parser.add_argument("--key-color", default="0,255,0")
    parser.add_argument("--tolerance", type=float, default=90.0)
    parser.add_argument("--pad", type=int, default=2)
    parser.add_argument("--no-trim", action="store_true")
    args = parser.parse_args()

    image = Image.open(args.src).convert("RGBA")
    if args.mode == "rembg":
        from rembg import remove  # imported lazily: it loads an onnx model
        image = remove(image).convert("RGBA")
    else:
        pixels = np.array(image)
        color = tuple(int(v) for v in args.key_color.split(","))
        pixels[:, :, 3] = key_alpha(pixels[:, :, :3], color, args.tolerance)
        pixels = despill(pixels, color)
        image = Image.fromarray(pixels, "RGBA")

    alpha = np.array(image)[:, :, 3]
    rows = np.where(alpha.max(axis=1) > 8)[0]
    cols = np.where(alpha.max(axis=0) > 8)[0]
    if rows.size == 0 or cols.size == 0:
        raise SystemExit("nothing left after cutout")
    box = (int(cols[0]), int(rows[0]), int(cols[-1]) + 1, int(rows[-1]) + 1)
    if not args.no_trim:
        pad = args.pad
        box = (max(box[0] - pad, 0), max(box[1] - pad, 0), min(box[2] + pad, image.width), min(box[3] + pad, image.height))
        image = image.crop(box)
    pathlib.Path(args.dst).parent.mkdir(parents=True, exist_ok=True)
    image.save(args.dst)
    print(f"wrote {args.dst} {image.width}x{image.height} bbox={box}")


if __name__ == "__main__":
    main()
