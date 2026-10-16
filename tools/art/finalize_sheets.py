#!/usr/bin/env python3
"""Finish animation sheets for shipping: strong de-spill of green fringes and WebP encoding.

    python3 tools/art/finalize_sheets.py game/assets/characters/knight [more folders...] [--quality 90]

For every anim/*.png in the given character folders: pulls remaining green out of edge pixels,
writes anim/<name>.webp, and removes the PNG (and its .import sidecar). SpriteSheetLoader
prefers .webp over .png. Only run on folders whose art is final.
"""
import argparse
import pathlib

import numpy as np
from PIL import Image


def strong_despill(pixels: np.ndarray) -> np.ndarray:
    rgb = pixels[:, :, :3].astype(np.float32)
    limit = np.maximum(rgb[:, :, 0], rgb[:, :, 2])
    excess = np.clip(rgb[:, :, 1] - limit, 0, None)
    # Painted characters never contain pure green: clamp green to the other channels' max.
    rgb[:, :, 1] = rgb[:, :, 1] - excess
    pixels[:, :, :3] = rgb.clip(0, 255).astype(np.uint8)
    # Also fade nearly transparent fringe pixels fully out.
    alpha = pixels[:, :, 3].astype(np.float32)
    pixels[:, :, 3] = np.where(alpha < 40, 0, alpha).astype(np.uint8)
    return pixels


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("folders", nargs="+")
    parser.add_argument("--quality", type=int, default=90)
    parser.add_argument("--keep-png", action="store_true")
    args = parser.parse_args()
    for folder in args.folders:
        anim = pathlib.Path(folder) / "anim"
        for png in sorted(anim.glob("*.png")):
            pixels = strong_despill(np.array(Image.open(png).convert("RGBA")))
            webp = png.with_suffix(".webp")
            Image.fromarray(pixels, "RGBA").save(webp, "WEBP", quality=args.quality, method=6)
            before = png.stat().st_size // 1024
            if not args.keep_png:
                png.unlink()
                sidecar = png.with_name(png.name + ".import")
                if sidecar.exists():
                    sidecar.unlink()
            print(f"{webp} {before} KB -> {webp.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
