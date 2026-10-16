#!/usr/bin/env python3
"""Generate an image with the Gemini API and record its cost.

    python3 tools/art/gen.py --prompt "..." --out path.png [--model M] [--aspect 1:1] [--size 1K]
                             [--ref image.png ...] [--style tools/art/style.txt] [--cap-usd 20]

The API key comes from GEMINI_API_KEY and is never printed. Every call appends a row to
tools/art/ledger.csv with the token counts and an estimated cost; the script refuses to run
once the ledger's total reaches the cap.
"""
import argparse
import base64
import csv
import datetime as dt
import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent
LEDGER = ROOT / "ledger.csv"
ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
# Estimated USD per million tokens (image output / text input). Conservative round numbers.
RATES = {
    "gemini-3.1-flash-image": (60.0, 0.5),
    "gemini-3.1-flash-image-preview": (60.0, 0.5),
    "gemini-3.1-flash-lite-image": (40.0, 0.5),
    "gemini-2.5-flash-image": (30.0, 0.3),
    "gemini-3-pro-image": (120.0, 2.0),
    "gemini-3-pro-image-preview": (120.0, 2.0),
}


def ledger_total(tag: str = "") -> float:
    if not LEDGER.exists():
        return 0.0
    with LEDGER.open() as handle:
        rows = list(csv.DictReader(handle))
    return sum(float(row["est_usd"]) for row in rows if not tag or row.get("tag") == tag)


def append_ledger(row: dict) -> None:
    import fcntl
    with LEDGER.open("a+", newline="") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        handle.seek(0, 2)
        writer = csv.DictWriter(handle, fieldnames=list(row.keys()))
        if handle.tell() == 0:
            writer.writeheader()
        writer.writerow(row)
        fcntl.flock(handle, fcntl.LOCK_UN)


def build_request(prompt: str, refs: list, aspect: str, size: str, model: str) -> dict:
    parts = []
    for ref in refs:
        data = pathlib.Path(ref).read_bytes()
        mime = "image/png" if ref.lower().endswith(".png") else "image/jpeg"
        parts.append({"inlineData": {"mimeType": mime, "data": base64.b64encode(data).decode()}})
    parts.append({"text": prompt})
    config = {"responseModalities": ["IMAGE"], "imageConfig": {"aspectRatio": aspect}}
    if not model.startswith("gemini-2.5"):
        config["imageConfig"]["imageSize"] = size
    return {"contents": [{"parts": parts}], "generationConfig": config}


def call(model: str, body: dict, key: str) -> dict:
    url = ENDPOINT.format(model=model)
    payload = json.dumps(body).encode()
    for attempt in range(5):
        request = urllib.request.Request(
            url, data=payload, method="POST",
            headers={"Content-Type": "application/json", "x-goog-api-key": key},
        )
        try:
            with urllib.request.urlopen(request, timeout=180) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            text = error.read().decode(errors="replace")
            if error.code in (429, 500, 502, 503, 504) and attempt < 4:
                wait = 4 * (attempt + 1)
                print(f"HTTP {error.code}, retrying in {wait}s", file=sys.stderr)
                time.sleep(wait)
                continue
            sys.exit(f"HTTP {error.code}: {text[:600]}")
    sys.exit("gave up after retries")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--prompt", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--model", default="gemini-3.1-flash-image")
    parser.add_argument("--aspect", default="1:1")
    parser.add_argument("--size", default="1K", choices=["1K", "2K", "4K"])
    parser.add_argument("--ref", action="append", default=[], help="reference image(s) sent before the prompt")
    parser.add_argument("--style", default=str(ROOT / "style.txt"), help="style text prepended to the prompt ('' for none)")
    parser.add_argument("--cap-usd", type=float, default=20.0, help="global ledger cap")
    parser.add_argument("--tag", default="", help="budget tag, e.g. hero, snail, backdrops")
    parser.add_argument("--tag-cap", type=float, default=0.0, help="cap for this tag (0 = none)")
    args = parser.parse_args()

    key = os.environ.get("GEMINI_API_KEY", "")
    if not key:
        sys.exit("GEMINI_API_KEY is not set")
    spent = ledger_total()
    if spent >= args.cap_usd:
        sys.exit(f"budget cap reached: ${spent:.2f} >= ${args.cap_usd:.2f}")
    if args.tag and args.tag_cap > 0 and ledger_total(args.tag) >= args.tag_cap:
        sys.exit(f"budget cap for tag '{args.tag}' reached (${ledger_total(args.tag):.2f})")

    prompt = args.prompt
    if args.style and pathlib.Path(args.style).exists():
        prompt = pathlib.Path(args.style).read_text().strip() + "\n\n" + prompt

    result = call(args.model, build_request(prompt, args.ref, args.aspect, args.size, args.model), key)
    candidates = result.get("candidates") or []
    image_parts = [p for c in candidates for p in c.get("content", {}).get("parts", []) if "inlineData" in p]
    usage = result.get("usageMetadata", {})
    prompt_tokens = int(usage.get("promptTokenCount", 0))
    output_tokens = int(usage.get("candidatesTokenCount", 0))
    out_rate, in_rate = RATES.get(args.model, (120.0, 2.0))
    est_usd = output_tokens * out_rate / 1e6 + prompt_tokens * in_rate / 1e6
    append_ledger({
        "time": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "tag": args.tag, "model": args.model, "size": args.size, "aspect": args.aspect,
        "prompt_tokens": prompt_tokens, "output_tokens": output_tokens,
        "est_usd": f"{est_usd:.4f}", "out": args.out, "prompt": args.prompt[:160].replace("\n", " "),
    })
    if not image_parts:
        finish = candidates[0].get("finishReason") if candidates else result.get("promptFeedback")
        sys.exit(f"no image returned (finish: {finish}); cost logged ${est_usd:.3f}")
    data = base64.b64decode(image_parts[0]["inlineData"]["data"])
    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(data)
    print(f"wrote {out} ({len(data)//1024} KB) est ${est_usd:.3f}, ledger total ${spent + est_usd:.2f}")


if __name__ == "__main__":
    main()
