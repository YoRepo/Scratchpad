#!/usr/bin/env python3
"""Convert still PNG art (props, backdrops, UI, items) to WebP for shipping.

    python3 tools/art/to_webp.py game/assets/props game/assets/backdrops [--quality 90] [--keep-png]

Writes <name>.webp next to each PNG and removes the PNG and its .import sidecar unless
--keep-png. Loaders (TextureFiles.load_texture) prefer .webp over .png, and props.json may
keep naming .png files.
"""
import argparse
import pathlib

from PIL import Image


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("folders", nargs="+")
    parser.add_argument("--quality", type=int, default=90)
    parser.add_argument("--keep-png", action="store_true")
    args = parser.parse_args()
    for folder in args.folders:
        for png in sorted(pathlib.Path(folder).glob("*.png")):
            image = Image.open(png)
            webp = png.with_suffix(".webp")
            image.save(webp, "WEBP", quality=args.quality, method=6)
            before = png.stat().st_size // 1024
            if not args.keep_png:
                png.unlink()
                sidecar = png.with_name(png.name + ".import")
                if sidecar.exists():
                    sidecar.unlink()
            print(f"{webp} {before} KB -> {webp.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
