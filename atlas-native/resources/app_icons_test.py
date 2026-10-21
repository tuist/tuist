"""Check shipped icon resources and packaging declarations with Python 3.11+."""

import json
from pathlib import Path
import plistlib
import struct
import tomllib
import unittest
import xml.etree.ElementTree as ET

native = Path(__file__).resolve().parents[1]
android_attribute = "{http://schemas.android.com/apk/res/android}"


def png_header(path):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"Not a PNG: {path}")
    return struct.unpack(">IIBB", data[16:26])


class AppIconTests(unittest.TestCase):
    def test_ios_catalog_images_are_opaque_and_correctly_sized(self):
        catalog = native / "ios/Resources/Assets.xcassets/AppIcon.appiconset"
        images = json.loads((catalog / "Contents.json").read_text())["images"]
        self.assertTrue(images)
        for image in images:
            with self.subTest(image=image):
                pixels = round(float(image["size"].split("x")[0]) *
                               int(image["scale"].removesuffix("x")))
                width, height, depth, color_type = png_header(catalog / image["filename"])
                self.assertEqual((width, height, depth, color_type), (pixels, pixels, 8, 2))

    def test_ios_targets_package_preview_and_home_screen_icons(self):
        manifest = tomllib.loads((native / "once.toml").read_text())
        plist = plistlib.loads((native / "ios/Info.plist").read_bytes())
        for target_name in ("AtlasIOS", "AtlasIOSDevice"):
            target = next(target for target in manifest["target"] if target["name"] == target_name)
            attrs = target["attrs"]
            self.assertEqual(attrs["app_icon"], "AppIcon")
            files = {path.name for pattern in attrs["resources"] for path in native.glob(pattern)}
            self.assertTrue(files)
            for key in ("CFBundleIcons", "CFBundleIcons~ipad"):
                icon = plist[key]["CFBundlePrimaryIcon"]
                self.assertEqual(icon["CFBundleIconName"], attrs["app_icon"])
                for name in icon["CFBundleIconFiles"]:
                    # Tuist preview uploads look up the iPhone's exact @2x filename.
                    device = "~ipad" if key.endswith("~ipad") and name != "AppIcon60x60" else ""
                    self.assertIn(f"{name}@2x{device}.png", files)
            self.assertIn("AppIcon60x60@3x.png", files)

    def test_android_launcher_has_raster_and_adaptive_resources(self):
        manifest = ET.parse(native / "android/AndroidManifest.xml")
        application = manifest.find("application")
        self.assertEqual(application.get(android_attribute + "icon"), "@mipmap/ic_launcher")
        for density, pixels in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
                                ("xxhdpi", 144), ("xxxhdpi", 192)):
            path = native / f"android/res/mipmap-{density}/ic_launcher.png"
            self.assertEqual(png_header(path), (pixels, pixels, 8, 2))
        adaptive = ET.parse(native / "android/res/mipmap-anydpi-v26/ic_launcher.xml")
        self.assertEqual(adaptive.find("foreground").get(android_attribute + "drawable"),
                         "@drawable/atlas_launcher_foreground")
        foreground = native / "android/res/drawable-nodpi/atlas_launcher_foreground.png"
        self.assertEqual(png_header(foreground), (432, 432, 8, 6))
        self.assertEqual(adaptive.find("background").get(android_attribute + "drawable"),
                         "@color/atlas_launcher_background")
        colors = ET.parse(native / "android/res/values/launcher.xml")
        self.assertEqual(colors.find("color[@name='atlas_launcher_background']").text, "#087CAA")


if __name__ == "__main__":
    unittest.main()
