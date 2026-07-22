#!/usr/bin/env python3
"""Render Voyage's cabin announcements to bundled audio.

Voyage never calls a speech API during a focus flight: the announcement space is
small and closed, so every line is rendered once here and shipped as AAC. That
keeps the cabin voice studio-quality, offline, private, and free at runtime.

Usage (system Python — some Homebrew/PlatformIO builds ship no CA bundle and
fail TLS against the API):
    export ELEVENLABS_API_KEY=...            # never committed, never shipped
    /usr/bin/python3 Scripts/generate_pa_audio.py --dry-run
    /usr/bin/python3 Scripts/generate_pa_audio.py --candidates
    /usr/bin/python3 Scripts/generate_pa_audio.py --voice crew --voice captain

The free ElevenLabs tier allows 10,000 characters a month and grants a
noncommercial licence requiring attribution, which Settings displays. Shipping
Voyage commercially means regenerating these clips under a paid plan.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OUTPUT_ROOT = REPO / "Voyage" / "Resources" / "PA"
MODEL = "eleven_multilingual_v2"
API = "https://api.elevenlabs.io/v1/text-to-speech"

# Shipped voices. Keys become directory names and match PAVoice.folder in Swift.
VOICES = {
    "crew": ("EXAVITQu4vr4xnSDxMaL", "Sarah — mature, reassuring"),
    "captain": ("nPczCjzI2devNBz1zQrb", "Brian — deep, resonant"),
}

# Extra voices rendered only by --candidates, for a listening test.
CANDIDATES = {
    **VOICES,
    "crew_alt": ("hpp4J3VqNfWAUOO0d1Us", "Bella — professional, warm"),
    "captain_alt": ("onwK4e9ZLuTAKqWW03F9", "Daniel — steady British broadcaster"),
}

# Must stay in sync with Airport.all in Voyage/Models/Airport.swift.
CITIES = [
    "Boston",
    "New York",
    "Miami",
    "Raleigh–Durham",
    "San Francisco",
    "Los Angeles",
    "Seattle",
    "Toronto",
    "Vancouver",
    "Regina",
]

# Lines carry no numbers: durations and countdowns are already on screen and in
# the Live Activity, and keeping them out of the audio makes a fixed set of
# clips cover every flight.
GLOBAL_LINES = {
    "welcome": "Welcome aboard. The cabin doors are closed and focus mode is now on. "
               "Sit back, and enjoy your flight.",
    "beverage": "The beverage cart is coming through. Take a moment for some water.",
    "preview": "Welcome aboard. This is your cabin crew. Your focus time is yours.",
}

CITY_LINES = {
    "midpoint": "We're halfway to {city}.",
    "descent": "Beginning our descent into {city}. Time to wrap up.",
    "landed": "Welcome to {city}. Session complete.",
    "layover": "Welcome to {city}. Your connection boards shortly.",
    "finalcall": "Final boarding call for your connecting flight to {city}.",
}

# Measured delivery: a cabin PA is calm and even, never expressive. Low style
# and high stability keep every clip in the same register so the announcements
# sound like one person on one aircraft.
VOICE_SETTINGS = {
    "stability": 0.55,
    "similarity_boost": 0.80,
    "style": 0.0,
    "use_speaker_boost": True,
}


def slug(city: str) -> str:
    """Mirror of PAClipLibrary.slug in Swift — keep both in step."""
    return re.sub(r"-+", "-", re.sub(r"[^a-z0-9]", "-", city.lower())).strip("-")


def lines() -> dict[str, str]:
    out = dict(GLOBAL_LINES)
    for key, template in CITY_LINES.items():
        for city in CITIES:
            # The en dash reads as a pause rather than a hyphen, so spell the
            # spoken form out while keeping the slug tied to the app's city name.
            spoken = city.replace("–", " ")
            out[f"{key}_{slug(city)}"] = template.format(city=spoken)
    return out


def synthesize(text: str, voice_id: str, key: str) -> bytes:
    request = urllib.request.Request(
        f"{API}/{voice_id}?output_format=mp3_44100_128",
        data=json.dumps({
            "text": text,
            "model_id": MODEL,
            "voice_settings": VOICE_SETTINGS,
        }).encode(),
        headers={"xi-api-key": key, "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read()


def write_m4a(mp3: bytes, destination: Path) -> None:
    """AAC at 64 kbps mono: transparent for speech at a third of the size."""
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".mp3", delete=False) as scratch:
        scratch.write(mp3)
        source = Path(scratch.name)
    try:
        subprocess.run(
            ["afconvert", "-f", "m4af", "-d", "aac", "-b", "64000",
             str(source), str(destination)],
            check=True, capture_output=True,
        )
    finally:
        source.unlink(missing_ok=True)


def render(voices: dict[str, tuple[str, str]], script: dict[str, str],
           key: str, root: Path) -> int:
    spent = 0
    for name, (voice_id, description) in voices.items():
        print(f"\n{name} ({description})")
        for clip, text in script.items():
            # Flat, voice-prefixed names: Xcode flattens resource directories
            # into the bundle root, so per-voice folders would collide there.
            destination = root / f"{name}_{clip}.m4a"
            try:
                write_m4a(synthesize(text, voice_id, key), destination)
            except urllib.error.HTTPError as error:
                detail = error.read().decode(errors="replace")[:400]
                sys.exit(f"\n{clip}: HTTP {error.code}\n{detail}")
            spent += len(text)
            print(f"  {clip:<28} {len(text):>4} chars")
    return spent


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true",
                        help="print the character budget without spending quota")
    parser.add_argument("--candidates", action="store_true",
                        help="render only the preview line, in every candidate voice")
    parser.add_argument("--voice", action="append", choices=sorted(VOICES),
                        help="render one shipped voice (repeatable; default is all)")
    parser.add_argument("--out", type=Path, default=OUTPUT_ROOT)
    args = parser.parse_args()

    script = {"preview": GLOBAL_LINES["preview"]} if args.candidates else lines()
    voices = CANDIDATES if args.candidates else {
        name: VOICES[name] for name in (args.voice or VOICES)
    }

    per_voice = sum(len(text) for text in script.values())
    total = per_voice * len(voices)
    print(f"{len(script)} clips x {len(voices)} voices = "
          f"{per_voice} chars each, {total} total")

    if args.dry_run:
        return

    key = os.environ.get("ELEVENLABS_API_KEY")
    if not key:
        sys.exit("ELEVENLABS_API_KEY is not set.")

    spent = render(voices, script, key, args.out)
    print(f"\nWrote {len(script) * len(voices)} clips to {args.out} ({spent} chars).")


if __name__ == "__main__":
    main()
