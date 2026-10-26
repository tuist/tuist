"""Separate Pip's existing painted artwork into an articulated, transparent rig.

Run with Pillow and NumPy installed. No model call, external artwork or build-time tooling
is required. Coordinates are in the original 513px canvas used by AtlasPipView.
The six original expressions remain untouched for Reduce Motion.
"""

from collections import deque
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter


catalog = Path(__file__).resolve().parents[1] / "ios/Resources/Assets.xcassets"
size = 513


def silhouette(image):
    """Keep the connected painted silhouette, not disconnected purple haze."""
    alpha = image.getchannel("A")
    solid = alpha.point(lambda value: 255 if value >= 230 else 0)
    pixels = solid.load()
    seen = set()
    largest = []
    for y in range(size):
        for x in range(size):
            if not pixels[x, y] or (x, y) in seen:
                continue
            region = []
            pending = deque([(x, y)])
            seen.add((x, y))
            while pending:
                point = pending.popleft()
                region.append(point)
                for neighbor in ((point[0] - 1, point[1]), (point[0] + 1, point[1]),
                                 (point[0], point[1] - 1), (point[0], point[1] + 1)):
                    nx, ny = neighbor
                    if 0 <= nx < size and 0 <= ny < size and pixels[nx, ny] and neighbor not in seen:
                        seen.add(neighbor)
                        pending.append(neighbor)
            if len(region) > len(largest):
                largest = region
    matte = Image.new("L", image.size)
    for point in largest:
        matte.putpixel(point, 255)
    # One edge pixel retains the original antialiasing, with no distant fog.
    matte = ImageChops.multiply(matte.filter(ImageFilter.MaxFilter(3)), alpha)
    result = image.copy()
    result.putalpha(matte.point(lambda value: min(255, round(value * 255 / 252))))
    return result


def path_mask(start, segments):
    """Supersample a traced cubic outline without an SVG runtime dependency."""
    points = [start]
    for control1, control2, end in segments:
        begin = points[-1]
        for step in range(1, 41):
            t = step / 40
            points.append(tuple((1 - t) ** 3 * begin[i] + 3 * (1 - t) ** 2 * t * control1[i]
                                + 3 * (1 - t) * t ** 2 * control2[i] + t ** 3 * end[i]
                                for i in (0, 1)))
    mask = Image.new("L", (size * 4, size * 4))
    ImageDraw.Draw(mask).polygon([(round(x * 4), round(y * 4)) for x, y in points], fill=255)
    return mask.resize((size, size), Image.Resampling.LANCZOS)


def masked(image, mask):
    result = image.copy()
    result.putalpha(ImageChops.multiply(image.getchannel("A"), mask))
    return result


def write(name, image):
    directory = catalog / f"{name}.imageset"
    directory.mkdir(exist_ok=True)
    entries = []
    for scale in (1, 2, 3):
        filename = f"{name}@{scale}x.png"
        image.resize((171 * scale, 171 * scale), Image.Resampling.LANCZOS).save(directory / filename, optimize=True)
        entries.append({"filename": filename, "idiom": "universal", "scale": f"{scale}x"})
    (directory / "Contents.json").write_text(json.dumps({
        "images": entries, "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n")


def generate():
    neutral = silhouette(Image.open(catalog / "PipNeutral.imageset/PipNeutral@3x.png").convert("RGBA"))
    # Follow the painted lower torso seam; feet overlap behind it at their ankles.
    body_mask = path_mask((0, 0), [
        ((171, 0), (342, 0), (513, 0)),
        ((513, 120), (513, 240), (513, 360)),
        ((463, 360), (463, 360), (440, 364)),
        ((418, 379), (388, 378), (365, 373)),
        ((345, 370), (323, 370), (301, 371)),
        ((285, 374), (275, 372), (265, 370)),
        ((240, 370), (215, 373), (192, 376)),
        ((164, 380), (139, 376), (120, 363)),
        ((80, 360), (40, 360), (0, 360)),
    ])
    body = masked(neutral, body_mask)
    left_foot = path_mask((199, 361), [
        ((223, 361), (247, 361), (272, 361)),
        ((270, 380), (267, 396), (266, 415)),
        ((265, 436), (257, 452), (231, 452)),
        ((214, 454), (186, 451), (176, 442)),
        ((163, 427), (177, 407), (192, 400)),
        ((195, 388), (197, 374), (199, 361)),
    ])
    right_foot = path_mask((298, 361), [
        ((320, 361), (343, 361), (366, 361)),
        ((367, 379), (368, 390), (372, 400)),
        ((389, 404), (402, 428), (393, 441)),
        ((386, 453), (320, 453), (307, 444)),
        ((300, 429), (301, 385), (298, 361)),
    ])
    write("PipLeftFoot", masked(neutral, left_foot))
    write("PipRightFoot", masked(neutral, right_foot))

    # Separate just the eyes, preserving the painted shading and tiny highlights.
    eyes_mask = Image.new("L", (size * 4, size * 4))
    draw = ImageDraw.Draw(eyes_mask)
    eye_bounds = ((195, 202, 274, 289), (307, 202, 383, 288))
    for bounds in eye_bounds:
        draw.ellipse(tuple(value * 4 for value in bounds), fill=255)
    eyes_mask = eyes_mask.resize((size, size), Image.Resampling.LANCZOS).filter(ImageFilter.GaussianBlur(1))
    write("PipEyes", masked(neutral, eyes_mask))

    # Fit the surrounding painted surface, excluding the eye and its shadow.
    # A softly blended quadratic continues the 3D light gradient without a
    # flat circular patch or any of the mouth bleeding into the eye backing.
    pixels = np.asarray(neutral).astype(float)
    yy, xx = np.mgrid[:size, :size]
    for left, top, right, bottom in eye_bounds:
        x = (xx - (left + right) / 2) / 60
        y = (yy - (top + bottom) / 2) / 65
        radius = x * x + y * y
        samples = ((radius > 0.85) & (radius < 1.8)
                   & (pixels[:, :, 2] > pixels[:, :, 0] * 1.06)
                   & (pixels[:, :, 2] > pixels[:, :, 1] * 1.06)
                   & (pixels[:, :, 3] >= 250))
        basis = np.stack([np.ones_like(x), x, y, x * x, x * y, y * y], axis=-1)
        coefficients = np.linalg.lstsq(basis[samples], pixels[samples, :3], rcond=None)[0]
        surface = np.array(body)
        surface[:, :, :3] = np.clip(basis @ coefficients, 0, 255).round().astype(np.uint8)
        healing = Image.new("L", (size, size))
        ImageDraw.Draw(healing).ellipse((left - 9, top - 9, right + 9, bottom + 9), fill=255)
        healing = healing.filter(ImageFilter.GaussianBlur(6))
        # The smile is original artwork, not part of the healed eye backing.
        ImageDraw.Draw(healing).rectangle((268, 270, 309, 294), fill=0)
        body = Image.composite(Image.fromarray(surface), body, healing)
    write("PipBody", body)

    # Reuse the original waving arm rather than the generated sheet: its light,
    # material and silhouette match Pip exactly. Trace its boundary where it
    # overlaps the torso; source alpha alone cannot separate those two parts.
    wave = silhouette(Image.open(catalog / "PipWave.imageset/PipWave@3x.png").convert("RGBA"))
    arm_mask = path_mask((362, 367), [
        ((365, 343), (369, 309), (385, 289)),
        ((397, 274), (414, 273), (430, 282)),
        ((450, 289), (450, 311), (438, 331)),
        ((422, 354), (393, 365), (362, 367)),
    ])
    arm = Image.new("RGBA", (size, size))
    arm.alpha_composite(masked(wave, arm_mask), (52, -12))
    write("PipArm", arm)


if __name__ == "__main__":
    generate()
