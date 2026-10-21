"""Generate checked-in launcher icons using Atlas's existing mark and azure color.

Run with Pillow and librsvg's rsvg-convert installed. Native builds need neither.
"""

from io import BytesIO
import json
from pathlib import Path
import subprocess

from PIL import Image

native = Path(__file__).resolve().parents[1]
mark = (native.parent / "atlas/priv/static/images/tuist-logo.svg").read_text()
mark = mark.replace("#6F2CFF", "#FFFFFF")
azure = "#087CAA"


def render_mark(size):
    rendered = subprocess.run([
        "rsvg-convert", "--width", str(size), "--height", str(size),
    ], input=mark.encode(), check=True, capture_output=True).stdout
    return Image.open(BytesIO(rendered)).convert("RGBA")


def icon(size):
    image = Image.new("RGB", (size, size), azure)
    foreground = render_mark(round(size * 0.6))
    offset = (size - foreground.width) // 2
    image.paste(foreground, (offset, offset), foreground)
    return image


catalog = native / "ios/Resources/Assets.xcassets/AppIcon.appiconset"
catalog.mkdir(parents=True, exist_ok=True)
for previous in catalog.glob("*.png"):
    previous.unlink()
images = []
for idiom, sizes, scales in (
    ("iphone", (20, 29, 40, 60), (2, 3)),
    ("ipad", (20, 29, 40, 76), (1, 2)),
    ("ipad", (83.5,), (2,)),
    ("ios-marketing", (1024,), (1,)),
):
    for size in sizes:
        for scale in scales:
            device = "~ipad" if idiom == "ipad" else ""
            filename = f"AppIcon{size}x{size}@{scale}x{device}.png"
            icon(round(size * scale)).save(catalog / filename, optimize=True)
            images.append({
                "filename": filename, "idiom": idiom,
                "size": f"{size}x{size}", "scale": f"{scale}x",
            })
(catalog / "Contents.json").write_text(json.dumps({
    "images": images, "info": {"author": "xcode", "version": 1},
}, indent=2) + "\n")

android = native / "android/res"
for density, size in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
                      ("xxhdpi", 144), ("xxxhdpi", 192)):
    directory = android / f"mipmap-{density}"
    directory.mkdir(parents=True, exist_ok=True)
    icon(size).save(directory / "ic_launcher.png", optimize=True)

# Adaptive icons use a 108dp layer with the mark inside the 66dp safe zone.
foreground = Image.new("RGBA", (432, 432))
foreground.alpha_composite(render_mark(216), (108, 108))
foreground.save(android / "drawable-nodpi/atlas_launcher_foreground.png", optimize=True)
adaptive = android / "mipmap-anydpi-v26"
adaptive.mkdir(parents=True, exist_ok=True)
(adaptive / "ic_launcher.xml").write_text('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/atlas_launcher_background" />
    <foreground android:drawable="@drawable/atlas_launcher_foreground" />
</adaptive-icon>
''')
(android / "values/launcher.xml").write_text(f'''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="atlas_launcher_background">{azure}</color>
</resources>
''')
