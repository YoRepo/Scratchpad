#!/usr/bin/env python3
"""Generate a short video clip through the Gemini API and record its cost.

    python3 tools/art/video.py --prompt "..." --first base.png --out clip.mp4 [--last base.png]
                               [--model gemini-omni-1.1-flash] [--seconds 8] [--aspect 16:9]
                               [--resolution 720p] [--negative "..."] [--tag hero --tag-cap 8]

Two backends behind one interface:
- Gemini Omni (model names starting with "gemini-omni"): the Interactions API, synchronous,
  3 to 10 s, 360p/720p/1080p/4k; the first and last frames are declared in the prompt as
  "[# Sources <FIRST_FRAME>@Image1 <LAST_FRAME>@Image2]". Cost comes from the usage tokens.
- Veo (model names starting with "veo"): predictLongRunning, 4/6/8 s, polled; cost per second.

The first frame image fixes the framing; a last frame makes the clip return to it (loops).
Every clip is appended to tools/art/ledger.csv.
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
# Gemini Omni bills by token: USD per million for video output, text/thought output, input.
OMNI_VIDEO_PER_M = 17.50
OMNI_TEXT_PER_M = 9.00
OMNI_INPUT_PER_M = 1.50


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


def omni_generate(args: argparse.Namespace, key: str, out: pathlib.Path) -> float:
    """Run one Gemini Omni interaction, write the mp4, return the estimated cost in USD."""
    sources = "<FIRST_FRAME>@Image1"
    items = [{"type": "image", "data": image_part(args.first)["bytesBase64Encoded"],
              "mime_type": image_part(args.first)["mimeType"]}]
    if args.last:
        same = pathlib.Path(args.last).resolve() == pathlib.Path(args.first).resolve()
        if not same:
            items.append({"type": "image", "data": image_part(args.last)["bytesBase64Encoded"],
                          "mime_type": image_part(args.last)["mimeType"]})
        sources += " <LAST_FRAME>@Image1" if same else " <LAST_FRAME>@Image2"
    prompt = f"[# Sources {sources}]\n{args.prompt}"
    if args.negative:
        prompt += f"\nAvoid: {args.negative}"
    body = {
        "model": args.model,
        "input": [{"type": "text", "text": prompt}] + items,
        "response_format": {"type": "video", "aspect_ratio": args.aspect,
                            "resolution": args.resolution, "duration": f"{args.seconds}s"},
    }
    result = request_json(f"{API}/interactions", key, body)
    if result.get("status") != "completed":
        sys.exit(f"interaction not completed: {json.dumps(result)[:600]}")
    videos = [content for step in result.get("steps", []) if step.get("type") == "model_output"
              for content in step.get("content", []) if content.get("type") == "video"]
    if not videos:
        sys.exit(f"no video in interaction: {json.dumps(result)[:600]}")
    video = videos[0]
    if "data" in video:
        out.write_bytes(base64.b64decode(video["data"]))
    elif "uri" in video:
        download(video["uri"], key, out)
    else:
        sys.exit(f"unknown video payload: {json.dumps(video)[:300]}")
    usage = result.get("usage", {})
    video_tokens = sum(entry.get("tokens", 0) for entry in usage.get("output_tokens_by_modality", [])
                       if entry.get("modality") == "video")
    other_output = usage.get("total_output_tokens", 0) - video_tokens
    cost = (video_tokens * OMNI_VIDEO_PER_M + other_output * OMNI_TEXT_PER_M
            + usage.get("total_input_tokens", 0) * OMNI_INPUT_PER_M) / 1e6
    print(f"omni interaction {result.get('id', '?')}: {video_tokens} video tokens", file=sys.stderr)
    return cost


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
    parser.add_argument("--model", default="gemini-omni-1.1-flash")
    parser.add_argument("--seconds", type=int, default=8, choices=range(3, 11))
    parser.add_argument("--aspect", default="16:9", choices=["16:9", "9:16"])
    parser.add_argument("--resolution", default="720p", choices=["360p", "720p", "1080p", "4k"])
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

    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    if args.model.startswith("gemini-omni"):
        est_usd = omni_generate(args, key, out)
        append_ledger({
            "time": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
            "tag": args.tag, "model": args.model, "size": args.resolution, "aspect": args.aspect,
            "prompt_tokens": 0, "output_tokens": args.seconds, "est_usd": f"{est_usd:.4f}",
            "out": args.out, "prompt": args.prompt[:160].replace("\n", " "),
        })
        print(f"wrote {out} ({out.stat().st_size // 1024} KB) est ${est_usd:.2f}, "
              f"ledger total ${spent + est_usd:.2f}")
        return
    if args.seconds not in (4, 6, 8) or args.resolution not in ("720p", "1080p"):
        sys.exit("Veo takes --seconds 4|6|8 and --resolution 720p|1080p")

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
