#!/usr/bin/env python3
"""Split a puppet parts sheet into separate transparent part images.

    python3 tools/art/split.py sheet.png out_dir [--min-area 1500] [--gap 6]

Runs the cutout, finds connected blobs of opaque pixels (bridging gaps up to --gap px),
saves each as out_dir/piece_NN.png, writes out_dir/pieces.json with their boxes, and
renders out_dir/contact.png: the sheet with every piece numbered, for picking roles.
"""
import argparse
import json
import pathlib

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("sheet")
    parser.add_argument("out_dir")
    parser.add_argument("--min-area", type=int, default=1500)
    parser.add_argument("--gap", type=int, default=6, help="bridge gaps this wide so a piece stays whole")
    parser.add_argument("--mode", default="key", choices=["key", "rembg"])
    parser.add_argument("--key-color", default="0,255,0")
    parser.add_argument("--tolerance", type=float, default=90.0)
    args = parser.parse_args()

    image = Image.open(args.sheet).convert("RGBA")
    if args.mode == "rembg":
        from rembg import remove
        image = remove(image).convert("RGBA")
        pixels = np.array(image)
    else:
        from cutout import key_alpha, despill
        pixels = np.array(image)
        color = tuple(int(v) for v in args.key_color.split(","))
        pixels[:, :, 3] = key_alpha(pixels[:, :, :3], color, args.tolerance)
        pixels = despill(pixels, color)
    mask = pixels[:, :, 3] > 24
    bridged = ndimage.binary_closing(mask, structure=np.ones((args.gap, args.gap)))
    labels, count = ndimage.label(bridged)
    out = pathlib.Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    pieces = []
    for label in range(1, count + 1):
        ys, xs = np.where((labels == label) & mask)
        if ys.size < args.min_area:
            continue
        box = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
        piece = np.zeros_like(pixels)
        sel = (labels == label)
        piece[sel] = pixels[sel]
        crop = Image.fromarray(piece, "RGBA").crop(box)
        pieces.append({"box": box, "area": int(ys.size), "cx": float(xs.mean()), "cy": float(ys.mean())})
        pieces[-1]["_crop"] = crop
    # Number pieces reading order: by row bands then x.
    pieces.sort(key=lambda p: (round(p["cy"] / 180), p["cx"]))
    contact = image.copy()
    draw = ImageDraw.Draw(contact)
    for index, piece in enumerate(pieces):
        name = f"piece_{index:02d}.png"
        piece.pop("_crop").save(out / name)
        piece["file"] = name
        x0, y0, x1, y1 = piece["box"]
        draw.rectangle(piece["box"], outline=(255, 0, 0, 255), width=3)
        draw.rectangle((x0, y0, x0 + 46, y0 + 30), fill=(255, 0, 0, 255))
        draw.text((x0 + 6, y0 + 4), f"{index:02d}", fill=(255, 255, 255, 255))
    for piece in pieces:
        piece["box"] = list(piece["box"])
    contact.save(out / "contact.png")
    (out / "pieces.json").write_text(json.dumps(pieces, indent=1))
    print(f"{len(pieces)} pieces -> {out}/ (contact.png, pieces.json)")
    for index, piece in enumerate(pieces):
        print(f"  {index:02d} box={piece['box']} area={piece['area']}")


if __name__ == "__main__":
    main()
