#!/usr/bin/env python3
"""Generate a short video clip with Veo through the Gemini API and record its cost.

    python3 tools/art/video.py --prompt "..." --first base.png --out clip.mp4 [--last base.png]
                               [--model veo-3.1-lite-generate-preview] [--seconds 8] [--aspect 16:9]
                               [--resolution 720p] [--negative "..."] [--tag hero --tag-cap 8]

The first frame image fixes the framing; a last frame makes the clip return to it (loops).
Cost is estimated per second of output and appended to tools/art/ledger.csv.
"""
import argparse
import base64
import datetime as dt
import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen import append_ledger, ledger_total  # noqa: E402

API = "https://generativelanguage.googleapis.com/v1beta"
# USD per second of output at 720p / 1080p (Google's published table, October 2026).
RATES = {
    "veo-3.1-lite-generate-preview": (0.05, 0.08),
    "veo-3.1-fast-generate-preview": (0.10, 0.12),
    "veo-3.1-generate-preview": (0.40, 0.40),
}


def image_part(path: str) -> dict:
    data = pathlib.Path(path).read_bytes()
    mime = "image/png" if path.lower().endswith(".png") else "image/jpeg"
    return {"bytesBase64Encoded": base64.b64encode(data).decode(), "mimeType": mime}


def request_json(url: str, key: str, body: dict | None = None) -> dict:
    payload = json.dumps(body).encode() if body is not None else None
    for attempt in range(6):
        request = urllib.request.Request(
            url, data=payload, method="POST" if body is not None else "GET",
            headers={"Content-Type": "application/json", "x-goog-api-key": key},
        )
        try:
            with urllib.request.urlopen(request, timeout=300) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            text = error.read().decode(errors="replace")
            if error.code in (429, 500, 502, 503, 504) and attempt < 5:
                wait = 10 * (attempt + 1)
                print(f"HTTP {error.code}, retrying in {wait}s", file=sys.stderr)
                time.sleep(wait)
                continue
            sys.exit(f"HTTP {error.code}: {text[:800]}")
    sys.exit("gave up after retries")


def download(uri: str, key: str, out: pathlib.Path) -> None:
    request = urllib.request.Request(uri, headers={"x-goog-api-key": key})
    with urllib.request.urlopen(request, timeout=600) as response:
        out.write_bytes(response.read())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--prompt", required=True)
    parser.add_argument("--first", required=True, help="first frame image (sets the framing)")
    parser.add_argument("--last", default="", help="optional last frame image")
    parser.add_argument("--out", required=True)
    parser.add_argument("--model", default="veo-3.1-lite-generate-preview")
    parser.add_argument("--seconds", type=int, default=8, choices=[4, 6, 8])
    parser.add_argument("--aspect", default="16:9", choices=["16:9", "9:16"])
    parser.add_argument("--resolution", default="720p", choices=["720p", "1080p"])
    parser.add_argument("--negative", default="")
    parser.add_argument("--cap-usd", type=float, default=22.0)
    parser.add_argument("--tag", default="video")
    parser.add_argument("--tag-cap", type=float, default=0.0)
    args = parser.parse_args()

    key = os.environ.get("GEMINI_API_KEY", "")
    if not key:
        sys.exit("GEMINI_API_KEY is not set")
    spent = ledger_total()
    if spent >= args.cap_usd:
        sys.exit(f"budget cap reached: ${spent:.2f} >= ${args.cap_usd:.2f}")
    if args.tag and args.tag_cap > 0 and ledger_total(args.tag) >= args.tag_cap:
        sys.exit(f"budget cap for tag '{args.tag}' reached (${ledger_total(args.tag):.2f})")

    instance = {"prompt": args.prompt, "image": image_part(args.first)}
    if args.last:
        instance["lastFrame"] = image_part(args.last)
    parameters = {"aspectRatio": args.aspect, "durationSeconds": args.seconds, "resolution": args.resolution}
    if args.negative:
        parameters["negativePrompt"] = args.negative
    body = {"instances": [instance], "parameters": parameters}

    started = request_json(f"{API}/models/{args.model}:predictLongRunning", key, body)
    name = started.get("name")
    if not name:
        sys.exit(f"no operation name in response: {json.dumps(started)[:400]}")
    print(f"operation {name}; polling", file=sys.stderr)
    for _ in range(120):
        time.sleep(10)
        status = request_json(f"{API}/{name}", key)
        if status.get("done"):
            break
    else:
        sys.exit("timed out waiting for the video")
    if "error" in status:
        sys.exit(f"generation failed: {json.dumps(status['error'])[:600]}")
    response = status.get("response", {})
    samples = (response.get("generateVideoResponse", {}).get("generatedSamples")
               or response.get("generatedSamples") or response.get("videos") or [])
    if not samples:
        sys.exit(f"no video in response: {json.dumps(response)[:600]}")
    video = samples[0].get("video", samples[0])
    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    if "uri" in video:
        download(video["uri"], key, out)
    elif "bytesBase64Encoded" in video:
        out.write_bytes(base64.b64decode(video["bytesBase64Encoded"]))
    else:
        sys.exit(f"unknown video payload: {json.dumps(video)[:300]}")
    rate = RATES.get(args.model, (0.40, 0.40))[0 if args.resolution == "720p" else 1]
    est_usd = rate * args.seconds
    append_ledger({
        "time": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "tag": args.tag, "model": args.model, "size": args.resolution, "aspect": args.aspect,
        "prompt_tokens": 0, "output_tokens": args.seconds, "est_usd": f"{est_usd:.4f}",
        "out": args.out, "prompt": args.prompt[:160].replace("\n", " "),
    })
    print(f"wrote {out} ({out.stat().st_size // 1024} KB) est ${est_usd:.2f}, ledger total ${spent + est_usd:.2f}")


if __name__ == "__main__":
    main()
