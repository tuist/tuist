"""Derive Atlas's native login assets from the existing Atlas mark and Tuist backdrop.

Run from any directory with Pillow and librsvg's rsvg-convert installed.
The generated assets are checked in; native builds do not run this script.
"""

import json
from pathlib import Path
import subprocess

from PIL import Image

native = Path(__file__).resolve().parents[1]
repo = native.parent
catalog = native / "ios/Resources/Assets.xcassets"
android = native / "android/res"
background_source = repo / "app/Resources/TuistApp/Assets.xcassets/LaunchScreenBackground.imageset"
mark = (repo / "atlas/priv/static/images/tuist-logo.svg").read_text().replace("#6F2CFF", "#FFFFFF")


def contents(directory, images):
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "Contents.json").write_text(json.dumps({
        "images": images,
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n")


catalog.mkdir(parents=True, exist_ok=True)
(catalog / "Contents.json").write_text('{"info":{"author":"xcode","version":1}}\n')
mark_dir = catalog / "AtlasMark.imageset"
mark_dir.mkdir(parents=True, exist_ok=True)
images = []
for scale in (1, 2, 3):
    filename = f"AtlasMark@{scale}x.png"
    rendered = subprocess.run([
        "rsvg-convert", "--width", str(40 * scale), "--height", str(40 * scale),
    ], input=mark.encode(), check=True, capture_output=True).stdout
    (mark_dir / filename).write_bytes(rendered)
    images.append({"filename": filename, "idiom": "universal", "scale": f"{scale}x"})
contents(mark_dir, images)
(android / "drawable-nodpi").mkdir(parents=True, exist_ok=True)
(android / "drawable-nodpi/atlas_mark.png").write_bytes(rendered)

background_dir = catalog / "AtlasLoginBackground.imageset"
background_dir.mkdir(parents=True, exist_ok=True)
images = []
for dark in (False, True):
    for scale in (1, 2, 3):
        suffix = "" if scale == 1 else f"@{scale}x"
        source = background_source / f"LaunchScreenBackground{suffix}{' 1' if dark else ''}.png"
        with Image.open(source) as original:
            hue, saturation, value = original.convert("HSV").split()
            hue = hue.point(lambda pixel: (pixel - 45) % 256)
            image = Image.merge("HSV", (hue, saturation, value)).convert("RGB")
        filename = f"AtlasLoginBackground{'Dark' if dark else ''}@{scale}x.png"
        entry = {"filename": filename, "idiom": "universal", "scale": f"{scale}x"}
        if dark:
            entry["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
        images.append(entry)
        image.save(background_dir / filename, optimize=True)
        if scale == 3:
            destination = android / ("drawable-night-nodpi" if dark else "drawable-nodpi")
            destination.mkdir(parents=True, exist_ok=True)
            image.save(destination / "atlas_login_background.png", optimize=True)
contents(background_dir, images)
