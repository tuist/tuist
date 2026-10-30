#!/usr/bin/env python3
"""Exercise the actual NSH Android renderer with an isolated, offline fixture."""
import argparse
import re
import subprocess
import tempfile
import time
import xml.etree.ElementTree as ET
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--adb", default="adb")
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--dark", action="store_true")
parser.add_argument("--large-text", action="store_true")
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)


def adb(*command):
    return subprocess.check_output([args.adb, *command])


def tree():
    adb("shell", "uiautomator", "dump", "/sdcard/atlas-card.xml")
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "ui.xml"
        adb("pull", "/sdcard/atlas-card.xml", str(path))
        content = path.read_text()
        args.output.joinpath("last-ui.xml").write_text(content)
        return ET.fromstring(content)


def wait_for(label, scroll=False):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        root = tree()
        for node in root.iter("node"):
            if label in [node.get("text"), node.get("content-desc")]:
                bounds = list(map(int, re.findall(r"\d+", node.attrib["bounds"])))
                if bounds[2] > bounds[0] and bounds[3] > bounds[1]:
                    return node
        if scroll:
            width, height = map(int, re.findall(r"(\d+)x(\d+)", adb("shell", "wm", "size").decode())[-1])
            adb("shell", "input", "swipe", str(width // 2), str(height * 3 // 4), str(width // 2), str(height // 3), "300")
        time.sleep(0.25)
    args.output.joinpath("failure.png").write_bytes(adb("exec-out", "screencap", "-p"))
    raise AssertionError(f"Missing rendered control: {label}")


scale = adb("shell", "settings", "get", "system", "font_scale").decode().strip()
night = adb("shell", "cmd", "uimode", "night").decode().strip().split()[-1]
try:
    adb("shell", "settings", "put", "system", "font_scale", "2.0" if args.large_text else "1.0")
    adb("shell", "cmd", "uimode", "night", "yes" if args.dark else "no")
    time.sleep(1)
    adb("shell", "am", "force-stop", "dev.tuist.atlas.preview")
    adb("shell", "am", "start", "-W", "-n", "dev.tuist.atlas.preview/.ThreadCardPreviewActivity")
    wait_for("Query comparison")
    wait_for("2.4× slower", scroll=True)
    source = wait_for("View source", scroll=True)
    args.output.joinpath("android-thread-nsh-card.png").write_bytes(adb("exec-out", "screencap", "-p"))
    x1, y1, x2, y2 = map(int, re.findall(r"\d+", source.attrib["bounds"]))
    density = int(re.findall(r"\d+", adb("shell", "wm", "density").decode())[-1]) / 160
    assert x2 > x1 and (y2 - y1) / density >= 47, "Source action must have a 48 dp touch target"
    adb("shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
    wait_for("Original source evidence", scroll=True)
    args.output.joinpath("android-thread-nsh-source.png").write_bytes(adb("exec-out", "screencap", "-p"))
    print("NSH table and typed source event passed (offline fixture)")
finally:
    adb("shell", "settings", "put", "system", "font_scale", scale)
    adb("shell", "cmd", "uimode", "night", night)
