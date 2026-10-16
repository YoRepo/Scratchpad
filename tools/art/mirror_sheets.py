#!/usr/bin/env python3
"""Mirror every animation sheet of a character horizontally, cell by cell.

    python3 tools/art/mirror_sheets.py game/assets/characters/knight

For art that came out facing left: the runtime assumes every sheet faces right and mirrors
it for the other direction. Flips each frame cell of anim/*.webp (or .png) in place and
moves the origin's x in the matching .json to the mirrored foot position.
"""
import json
import pathlib
import sys

from PIL import Image, ImageOps


def mirror(folder: pathlib.Path) -> None:
    for meta_path in sorted((folder / "anim").glob("*.json")):
        meta = json.loads(meta_path.read_text())
        sheet_path = next((p for p in (meta_path.with_suffix(".webp"), meta_path.with_suffix(".png")) if p.exists()), None)
        if sheet_path is None:
            continue
        sheet = Image.open(sheet_path).convert("RGBA")
        width, height, columns = meta["width"], meta["height"], meta["columns"]
        for index in range(meta["frames"]):
            row, column = divmod(index, columns)
            box = (column * width, row * height, (column + 1) * width, (row + 1) * height)
            sheet.paste(ImageOps.mirror(sheet.crop(box)), box)
        if sheet_path.suffix == ".webp":
            sheet.save(sheet_path, "WEBP", quality=90, method=6)
        else:
            sheet.save(sheet_path, optimize=True)
        meta["origin"] = [round(width - meta["origin"][0], 2), meta["origin"][1]]
        meta_path.write_text(json.dumps(meta, indent=1))
        print(f"mirrored {sheet_path.name}: origin x -> {meta['origin'][0]}")


if __name__ == "__main__":
    mirror(pathlib.Path(sys.argv[1]))
