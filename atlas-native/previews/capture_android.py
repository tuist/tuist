"""Smoke-test the native Settings preview and capture screenshots outside the checkout."""

import argparse
from pathlib import Path
import re
import subprocess
import tempfile
import time
import xml.etree.ElementTree as ET


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    checkout = Path(__file__).resolve().parents[1]
    output = args.output.resolve()
    if output.is_relative_to(checkout):
        parser.error("Keep screenshot assets outside atlas-native/")
    output.mkdir(parents=True, exist_ok=True)

    def adb(*command, capture=False):
        return subprocess.run(
            [args.adb, *command], check=True, capture_output=capture,
            timeout=30,
        ).stdout

    def hierarchy():
        with tempfile.TemporaryDirectory() as directory:
            dumped = adb("shell", "uiautomator", "dump", "/sdcard/atlas-settings-preview.xml", capture=True)
            if b"dumped to:" not in dumped:
                return ET.ElementTree(ET.Element("hierarchy"))
            path = Path(directory) / "hierarchy.xml"
            adb("pull", "/sdcard/atlas-settings-preview.xml", str(path), capture=True)
            return ET.parse(path)

    def find(label):
        for _ in range(5):
            tree = hierarchy()
            for node in tree.iter("node"):
                if label.casefold() in (node.get("text", "").casefold(), node.get("content-desc", "").casefold()):
                    return node, tree
            time.sleep(0.2)
        raise AssertionError(f"Native control not found: {label}")

    def tap(label):
        node, _ = find(label)
        x1, y1, x2, y2 = map(int, re.findall(r"\d+", node.get("bounds")))
        adb("shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))

    def screenshot(name):
        (output / f"{name}.png").write_bytes(adb("exec-out", "screencap", "-p", capture=True))

    adb("install", "-r", str(checkout / ".once/out/AtlasSettingsAndroidPreview/AtlasSettingsAndroidPreview.apk"))
    adb("shell", "am", "force-stop", "dev.tuist.atlas.preview")
    adb("shell", "am", "start", "-n", "dev.tuist.atlas.preview/dev.tuist.atlas.preview.SettingsPreviewActivity")
    find("Not connected")
    find("Settings")
    screenshot("android-settings")
    tap("Claude")
    _, tree = find("Claude token")
    assert any(node.get("password") == "true" for node in tree.iter("node")), "Claude entry must be secure"
    screenshot("android-claude")
    tap("Cancel")
    tap("ChatGPT")
    tap("Sign in with ChatGPT")
    find("DEMO-CODE")
    screenshot("android-chatgpt")
    tap("Cancel sign-in")
    find("Sign in with ChatGPT")
    assert not any(node.get("text") == "DEMO-CODE" for node in hierarchy().iter("node"))
    tap("Navigate up")
    find("Settings")
    print("Native Android Settings, secure Claude input, ChatGPT instructions, cancellation and toolbar navigation passed.")


if __name__ == "__main__":
    main()
