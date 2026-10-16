#!/usr/bin/env python3
"""Check a walk sheet for a moonwalk and report its stride speed.

    python3 tools/art/stride.py game/assets/characters/knight/anim/walk.json

For a right-facing walk animated in place the foot on the ground must slide left (backward)
from frame to frame. Prints each frame's grounded-foot span, the share of frames in which the
grounded foot moves backward, and the average slide in world px/s at the sheet's fps (read
world_height / source_height / frame_scale from the character.json next to the anim folder),
which should be close to the run speed the sheet is played at.
"""
import json
import pathlib
import sys

import numpy as np
from PIL import Image


def grounded_span(alpha: np.ndarray) -> tuple[int, int] | None:
    rows = np.where(alpha.max(axis=1) > 100)[0]
    if len(rows) == 0:
        return None
    band = alpha[rows.max() - 6:rows.max() + 1]
    xs = np.where(band.max(axis=0) > 100)[0]
    clusters = np.split(xs, np.where(np.diff(xs) > 6)[0] + 1)
    widest = max(clusters, key=len)
    return int(widest.min()), int(widest.max())


def main() -> None:
    meta_path = pathlib.Path(sys.argv[1])
    meta = json.loads(meta_path.read_text())
    sheet_path = next(p for p in (meta_path.with_suffix(".webp"), meta_path.with_suffix(".png")) if p.exists())
    sheet = np.array(Image.open(sheet_path).convert("RGBA"))[:, :, 3]
    width, height, columns = meta["width"], meta["height"], meta["columns"]
    character = json.loads((meta_path.parent.parent / "character.json").read_text())
    world_per_px = character["world_height"] / (character["source_height"] * character["frame_scale"])
    spans = []
    for index in range(meta["frames"]):
        row, column = divmod(index, columns)
        spans.append(grounded_span(sheet[row * height:(row + 1) * height, column * width:(column + 1) * width]))
    backward = forward = 0
    slides = []
    for index in range(1, len(spans)):
        a, b = spans[index - 1], spans[index]
        if a is None or b is None:
            continue
        overlap = min(a[1], b[1]) - max(a[0], b[0])
        if overlap < 4:
            continue  # the other foot took over
        delta = (b[0] + b[1]) / 2 - (a[0] + a[1]) / 2
        slides.append(abs(delta))
        backward += delta < 0
        forward += delta > 0
        print(f"frame {index:2d}: grounded foot {a} -> {b}  {'backward' if delta < 0 else 'FORWARD'}")
    total = backward + forward
    rate = (np.mean(slides) if slides else 0.0) * world_per_px * meta["fps"]
    verdict = "ok: feet push backward" if total and backward / total >= 0.7 else "MOONWALK: feet slide forward"
    print(f"{meta['name']}: {backward}/{total} transitions backward -> {verdict}; "
          f"stride slide {rate:.0f} world px/s at {meta['fps']:.0f} fps")


if __name__ == "__main__":
    main()
