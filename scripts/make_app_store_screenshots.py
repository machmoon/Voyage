#!/usr/bin/env python3
"""Composites App Store Connect ready screenshots from the raw simulator captures in QA/.

Reads captions and layout from AppStore/screenshots.json and writes finished 6.9 inch
(1320x2868) PNGs to AppStore/screenshots/. Slots whose source capture does not exist yet are
reported and skipped, so this can be run repeatedly as the screenshot tour grows.

    python3 scripts/make_app_store_screenshots.py
    python3 scripts/make_app_store_screenshots.py --slots 1,2,3
    python3 scripts/make_app_store_screenshots.py --list

Dependencies: Pillow and the system SF fonts. Both ship with the machine this repo is
developed on; nothing needs installing.

Design lineage
--------------
The layout and the config format follow fastlane's frameit rather than inventing a scheme:

  fastlane/fastlane, frameit/lib/frameit/editor.rb

Taken from it:

  * The composition order in `complex_framing`: generate the background, draw the text into
    the background, size the device image, then composite the device into the background.
    `render()` below follows that same sequence for the same reason, which is that the text
    block claims its space first and the device gets what is left.
  * The `Framefile.json` schema: a `default` block of shared settings plus a `data` array
    whose entries bind to a source file by a `filter` substring of the filename. See
    AppStore/screenshots.json.
  * frameit's `keyword` above `title` text pairing, and its `padding` and `title_below_image`
    ideas.

Deviations, each deliberate:

  * frameit downloads Apple and Facebook device-frame art to draw a bezel around the
    screenshot. That art is not ours to redistribute, so this script draws the screenshot with
    rounded corners on a solid ground and no bezel. Several current top-grossing focus apps
    ship exactly that treatment, so this is a normal look rather than a compromise.
  * frameit has `keyword` and `title` only. Voyage's caption treatment is a three-part
    kicker, headline and support line, so a `subtitle` key is added. Same styling model.
  * frameit bleeds the device off the bottom of the canvas. Kept, because it reads as a
    designed asset rather than a screen grab.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit(
        "Pillow is required.\n"
        "  python3 -m pip install --user Pillow\n"
        "It is normally already present on this machine."
    )

REPO = Path(__file__).resolve().parent.parent
CONFIG = REPO / "AppStore" / "screenshots.json"
SOURCE_DIR = REPO / "QA"
OUTPUT_DIR = REPO / "AppStore" / "screenshots"

# System fonts. SFNS is the San Francisco family the app itself renders in, so the captions
# and the UI in the screenshot share a typeface.
FONT_CANDIDATES = [
    "/System/Library/Fonts/SFNS.ttf",
    "/System/Library/Fonts/HelveticaNeue.ttc",
    "/System/Library/Fonts/Helvetica.ttc",
]

# Captures known to be invalid. The screenshot tour run that produced qa-09 was killed by a
# scene-create watchdog, so that file is a picture of the iOS home screen rather than the app.
# Refuse to composite it: shipping it would be worse than shipping nothing.
QUARANTINE = {
    "qa-09-map-route": "capture is the iOS home screen, not the app (tour run was killed by "
                       "the launch-time scene watchdog). Re-run the tour after the crash fix.",
}


def load_font(size: int, weight: str = "bold") -> ImageFont.FreeTypeFont:
    """Best available system font at `size`. SFNS is variable, so weight is approximated by
    Pillow's own selection; we ask for the bold face where the file exposes one."""
    for path in FONT_CANDIDATES:
        if not Path(path).exists():
            continue
        try:
            font = ImageFont.truetype(path, size)
        except OSError:
            continue
        # SFNS.ttf is a variable font. Set the weight axis where Pillow supports it.
        try:
            axes = font.get_variation_axes()
            if axes:
                wght = 700 if weight == "bold" else (600 if weight == "semibold" else 400)
                coords = []
                for axis in axes:
                    name = axis.get("name")
                    name = name.decode() if isinstance(name, bytes) else str(name)
                    if "eight" in name:  # "Weight"
                        lo, hi = axis["minimum"], axis["maximum"]
                        coords.append(max(lo, min(hi, wght)))
                    else:
                        coords.append(axis["default"])
                font.set_variation_by_axes(coords)
        except (OSError, AttributeError):
            pass  # Static font, or no variation support. The default face is fine.
        return font
    raise SystemExit("No usable system font found. Looked for: " + ", ".join(FONT_CANDIDATES))


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def merged(default: dict, override: dict, key: str) -> dict:
    """`data` entry settings layered over `default`, which is how frameit resolves a
    Framefile entry."""
    out = dict(default.get(key, {}))
    out.update(override.get(key, {}))
    return out


def draw_tracked(draw: ImageDraw.ImageDraw, xy, text, font, fill, tracking: int) -> None:
    """Letter-spaced text. Pillow has no tracking, and the app's kicker style depends on it,
    so glyphs are advanced individually."""
    x, y = xy
    for char in text:
        draw.text((x, y), char, font=font, fill=fill)
        x += draw.textlength(char, font=font) + tracking


def tracked_width(draw: ImageDraw.ImageDraw, text, font, tracking: int) -> float:
    return sum(draw.textlength(c, font=font) for c in text) + tracking * max(0, len(text) - 1)


def rounded(image: Image.Image, radius: int) -> Image.Image:
    """Rounded corners with an antialiased mask, so the device edge is not a staircase."""
    scale = 4
    mask = Image.new("L", (image.width * scale, image.height * scale), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, mask.width - 1, mask.height - 1), radius=radius * scale, fill=255
    )
    mask = mask.resize(image.size, Image.LANCZOS)
    out = image.convert("RGBA")
    out.putalpha(mask)
    return out


def find_source(filter_token: str) -> Path | None:
    matches = sorted(p for p in SOURCE_DIR.glob("*.png") if filter_token in p.name)
    return matches[0] if matches else None


def render(entry: dict, defaults: dict, size: tuple[int, int], source: Path) -> Image.Image:
    """Compose one slot.

    Order follows frameit's `complex_framing` (frameit/lib/frameit/editor.rb): background
    first, then the text into the background, then size the device, then composite it in.
    """
    width, height = size
    padding = int(entry.get("padding", defaults.get("padding", 96)))
    background = entry.get("background", defaults.get("background", "#0B1020"))

    # 1. Background.
    canvas = Image.new("RGB", (width, height), hex_to_rgb(background))
    draw = ImageDraw.Draw(canvas)

    keyword = merged(defaults, entry, "keyword")
    title = merged(defaults, entry, "title")
    subtitle = merged(defaults, entry, "subtitle")

    # 2. Text into the background. The text block owns the top of the canvas and the device
    # receives whatever vertical space is left, which is frameit's `device_top` behaviour.
    y = padding + 24

    if keyword.get("text"):
        font = load_font(int(keyword.get("font_size", 34)), "semibold")
        text = keyword["text"].upper() if keyword.get("uppercase", True) else keyword["text"]
        tracking = int(keyword.get("tracking", 6))
        x = (width - tracked_width(draw, text, font, tracking)) / 2
        draw_tracked(draw, (x, y), text, font, hex_to_rgb(keyword.get("color", "#4E8CFF")), tracking)
        y += font.size + 34

    if title.get("text"):
        font = load_font(int(title.get("font_size", 92)), "bold")
        spacing = int(title.get("line_spacing", 12))
        for line in title["text"].split("\n"):
            w = draw.textlength(line, font=font)
            draw.text(((width - w) / 2, y), line, font=font,
                      fill=hex_to_rgb(title.get("color", "#FFFFFF")))
            y += font.size + spacing
        y += 18

    if subtitle.get("text"):
        font = load_font(int(subtitle.get("font_size", 44)), "regular")
        spacing = int(subtitle.get("line_spacing", 8))
        for line in subtitle["text"].split("\n"):
            w = draw.textlength(line, font=font)
            draw.text(((width - w) / 2, y), line, font=font,
                      fill=hex_to_rgb(subtitle.get("color", "#9AA5BD")))
            y += font.size + spacing

    # 3. Size the device image to the remaining width, and let it bleed off the bottom edge.
    device_top = int(y + padding * 0.9)
    shot = Image.open(source).convert("RGB")
    target_w = width - padding * 2
    target_h = round(shot.height * (target_w / shot.width))
    shot = shot.resize((target_w, target_h), Image.LANCZOS)
    shot = rounded(shot, int(entry.get("corner_radius", defaults.get("corner_radius", 64))))

    # 4. Composite the device into the background.
    canvas.paste(shot, (padding, device_top), shot)
    return canvas


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--config", type=Path, default=CONFIG)
    parser.add_argument("--out", type=Path, default=OUTPUT_DIR)
    parser.add_argument("--slots", help="Comma separated slot numbers, e.g. 1,2,3")
    parser.add_argument("--list", action="store_true",
                        help="Report the readiness of every slot and exit")
    args = parser.parse_args()

    config = json.loads(args.config.read_text())
    defaults = config.get("default", {})
    size = tuple(config.get("output_size", [1320, 2868]))
    wanted = {int(s) for s in args.slots.split(",")} if args.slots else None

    ready, blocked = [], []
    for entry in config["data"]:
        slot = entry["slot"]
        source = find_source(entry["filter"])
        if entry.get("blocked"):
            # An editorial block: the capture composites fine but the screen states something
            # the app does not do. Refusing here is the same principle as QUARANTINE.
            blocked.append((slot, entry["filter"], entry["blocked"]))
        elif source is None:
            blocked.append((slot, entry["filter"], "no capture matching this filter in QA/"))
        elif source.stem in QUARANTINE:
            blocked.append((slot, entry["filter"], QUARANTINE[source.stem]))
        else:
            ready.append((slot, entry, source))

    if args.list:
        print(f"{len(ready)} of {len(config['data'])} slots ready\n")
        for slot, _, source in ready:
            print(f"  slot {slot}  READY    {source.name}")
        for slot, token, why in blocked:
            print(f"  slot {slot}  BLOCKED  {token}: {why}")
        return 0

    args.out.mkdir(parents=True, exist_ok=True)
    written = 0
    for slot, entry, source in ready:
        if wanted and slot not in wanted:
            continue
        image = render(entry, defaults, size, source)
        path = args.out / f"{slot:02d}-{entry['filter']}.png"
        image.save(path, "PNG", optimize=True)
        print(f"slot {slot}  wrote {path.relative_to(REPO)}  ({image.width}x{image.height})")
        written += 1

    for slot, token, why in blocked:
        if wanted and slot not in wanted:
            continue
        print(f"slot {slot}  BLOCKED  {token}: {why}", file=sys.stderr)

    print(f"\n{written} written, {len(blocked)} blocked. Output: {args.out.relative_to(REPO)}")
    if blocked:
        print("Re-run once the missing captures exist. Nothing else needs changing.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
