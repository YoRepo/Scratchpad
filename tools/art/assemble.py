#!/usr/bin/env python3
"""Render a puppet manifest at rest pose so a rig can be checked without Godot.

    python3 tools/art/assemble.py game/assets/characters/knight/puppet.json out.png [--scale 0.5]

Draws every part at its attach point (parent-relative pivots), marks each pivot with a
red dot and the ground line in blue. See tools/art/CONVENTIONS.md for the manifest format.
"""
import argparse
import json
import pathlib

from PIL import Image, ImageDraw


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("manifest")
    parser.add_argument("out")
    parser.add_argument("--scale", type=float, default=0.5, help="preview scale relative to sheet pixels")
    args = parser.parse_args()

    manifest_path = pathlib.Path(args.manifest)
    manifest = json.loads(manifest_path.read_text())
    folder = manifest_path.parent
    parts = {part["name"]: part for part in manifest["parts"]}
    images = {name: Image.open(folder / part["file"]).convert("RGBA") for name, part in parts.items()}

    # World position (sheet pixels) of each part's pivot, root at (0, 0).
    positions = {}

    def pivot_position(name: str):
        if name in positions:
            return positions[name]
        part = parts[name]
        parent = part.get("parent")
        if parent is None:
            positions[name] = (0.0, 0.0)
        else:
            px, py = pivot_position(parent)
            parent_image = images[parent]
            parent_pivot = parts[parent]["pivot"]
            ax, ay = part["attach"]
            positions[name] = (
                px + (ax - parent_pivot[0]) * parent_image.width,
                py + (ay - parent_pivot[1]) * parent_image.height,
            )
        return positions[name]

    boxes = []
    for name, part in parts.items():
        x, y = pivot_position(name)
        image = images[name]
        left = x - part["pivot"][0] * image.width
        top = y - part["pivot"][1] * image.height
        boxes.append((left, top, left + image.width, top + image.height))
    min_x = min(b[0] for b in boxes) - 20
    min_y = min(b[1] for b in boxes) - 20
    max_x = max(b[2] for b in boxes) + 20
    max_y = max(b[3] for b in boxes) + 20
    width = int((max_x - min_x) * args.scale)
    height = int((max_y - min_y) * args.scale)
    canvas = Image.new("RGBA", (width, height), (120, 160, 120, 255))

    ordered = sorted(parts.values(), key=lambda part: part.get("z", 0))
    for part in ordered:
        if part.get("hidden"):
            continue
        name = part["name"]
        image = images[name]
        x, y = pivot_position(name)
        left = (x - part["pivot"][0] * image.width - min_x) * args.scale
        top = (y - part["pivot"][1] * image.height - min_y) * args.scale
        resized = image.resize((max(1, int(image.width * args.scale)), max(1, int(image.height * args.scale))))
        canvas.alpha_composite(resized, (int(left), int(top)))

    draw = ImageDraw.Draw(canvas)
    for name in parts:
        x, y = pivot_position(name)
        cx = (x - min_x) * args.scale
        cy = (y - min_y) * args.scale
        draw.ellipse((cx - 4, cy - 4, cx + 4, cy + 4), fill=(255, 0, 0, 255))
    ground = manifest.get("hip_to_ground_px")
    if ground is not None:
        gy = (ground - min_y) * args.scale
        draw.line((0, gy, width, gy), fill=(40, 80, 255, 255), width=2)
    pathlib.Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    canvas.save(args.out)
    print(f"wrote {args.out} {width}x{height}")


if __name__ == "__main__":
    main()
