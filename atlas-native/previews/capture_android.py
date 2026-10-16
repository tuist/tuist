"""Smoke-test native Settings or employee time off and capture fixture-backed screenshots."""

import argparse
from pathlib import Path
import re
import struct
import subprocess
import tempfile
import time
import xml.etree.ElementTree as ET


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--dark", action="store_true")
    parser.add_argument("--large-text", action="store_true")
    parser.add_argument("--landscape", action="store_true")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--time-off", action="store_true")
    mode.add_argument("--workspace", action="store_true")
    args = parser.parse_args()
    checkout = Path(__file__).resolve().parents[1]
    output = args.output.resolve()
    if output.is_relative_to(checkout.parent):
        parser.error("Keep screenshot assets outside the repository")
    output.mkdir(parents=True, exist_ok=True)
    suffix = ("-dark" if args.dark else "") + ("-large-text" if args.large_text else "") + ("-landscape" if args.landscape else "")

    def adb(*command, capture=False, timeout=30):
        return subprocess.run([args.adb, *command], check=True, capture_output=capture, timeout=timeout).stdout

    def hierarchy():
        with tempfile.TemporaryDirectory() as directory:
            dumped = adb("shell", "uiautomator", "dump", "/sdcard/atlas-settings-preview.xml", capture=True, timeout=90)
            if b"dumped to:" not in dumped:
                return ET.ElementTree(ET.Element("hierarchy"))
            path = Path(directory) / "hierarchy.xml"
            adb("pull", "/sdcard/atlas-settings-preview.xml", str(path), capture=True)
            return ET.parse(path)

    def swipe(up):
        image = adb("exec-out", "screencap", "-p", capture=True)
        width, height = struct.unpack(">II", image[16:24])
        start, end = (0.8, 0.35) if up else (0.35, 0.8)
        adb("shell", "input", "swipe", str(width // 2), str(int(height * start)), str(width // 2), str(int(height * end)), "300")

    def find(label, scroll=False, clickable=False):
        for attempt in range(6):
            tree = hierarchy()
            for node in tree.iter("node"):
                labels = (node.get("text", ""), node.get("text", "").partition("\n")[0], node.get("content-desc", ""), node.get("resource-id", ""))
                if label.casefold() in (value.casefold() for value in labels) and (
                    not clickable or node.get("clickable") == "true"
                ):
                    return node, tree
            if scroll and attempt >= 1:
                swipe(True)
            time.sleep(0.2)
        raise AssertionError(f"Native control not found: {label}")

    def tap(label, clickable=False):
        node, _ = find(label, scroll=True, clickable=clickable)
        x1, y1, x2, y2 = map(int, re.findall(r"\d+", node.get("bounds")))
        adb("shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))

    def screenshot(name):
        (output / f"{name}{suffix}.png").write_bytes(adb("exec-out", "screencap", "-p", capture=True))

    def minimum_target(label):
        node, _ = find(label, scroll=True)
        x1, y1, x2, y2 = map(int, re.findall(r"\d+", node.get("bounds")))
        density = int(re.findall(r"\d+", adb("shell", "wm", "density", capture=True).decode())[-1]) / 160
        assert x2 - x1 >= 48 * density - 1 and y2 - y1 >= 48 * density - 1, (label, node.get("bounds"))

    def setting(name):
        return adb("shell", "settings", "get", "system", name, capture=True).decode().strip()

    original = {name: setting(name) for name in ("font_scale", "accelerometer_rotation", "user_rotation")}
    night = adb("shell", "cmd", "uimode", "night", capture=True).decode().split(":")[-1].strip()
    try:
        adb("shell", "cmd", "uimode", "night", "yes" if args.dark else "no", capture=True)
        adb("shell", "settings", "put", "system", "font_scale", "2.0" if args.large_text else "1.0")
        adb("shell", "settings", "put", "system", "accelerometer_rotation", "0")
        adb("shell", "settings", "put", "system", "user_rotation", "1" if args.landscape else "0")
        adb("install", "-r", str(checkout / ".once/out/AtlasSettingsAndroidPreview/AtlasSettingsAndroidPreview.apk"))
        adb("shell", "am", "force-stop", "dev.tuist.atlas.preview")
        if args.workspace:
            activity = "dev.tuist.atlas.preview/dev.tuist.atlas.preview.WorkspacePreviewActivity"
            adb("shell", "am", "start", "-n", activity)
            find("My work", scroll=True)
            minimum_target("Time off")
            screenshot("android-workspace-home")
            tap("Commercial", clickable=True)
            tap("Sales", clickable=True)
            minimum_target("Accounts")
            screenshot("android-workspace-sales")
            tap("Accounts", clickable=True)
            find("https://atlas.example.org/commercial/sales/accounts")
            tap("Done")
            tap("Navigate up")
            find("Commercial")
            tap("Navigate up")
            tap("People", clickable=True)
            tap("Time off", clickable=True)
            find("Edit request", scroll=True)
            adb("shell", "input", "keyevent", "KEYCODE_BACK")
            find("People")
            tap("Settings")
            find("Settings")
            adb("shell", "input", "keyevent", "KEYCODE_BACK")
            find("People")
            tap("Navigate up")
            tap("android:id/search_src_text")
            adb("shell", "input", "text", "vendor")
            adb("shell", "input", "keyevent", "KEYCODE_ENTER")
            minimum_target("Vendor costs")
            screenshot("android-workspace-search")
            tap("Vendor costs", clickable=True)
            find("https://atlas.example.org/commercial/finance/vendors")
            tap("Done")
            tap("Navigate up")
            find("My work", scroll=True)
            tap("Commercial", clickable=True)
            tap("Finance", clickable=True)
            tap("android:id/search_src_text")
            adb("shell", "input", "text", "vendor")
            adb("shell", "input", "keyevent", "KEYCODE_ENTER")
            find("Vendor costs", scroll=True)
            adb("shell", "settings", "put", "system", "user_rotation", "0" if args.landscape else "1")
            find("Vendor costs", scroll=True)
            adb("shell", "settings", "put", "system", "user_rotation", "1" if args.landscape else "0")
            find("Vendor costs", scroll=True)
            screenshot("android-workspace-restored-search")
            adb("shell", "input", "keyevent", "KEYCODE_BACK")
            find("Finance overview", scroll=True)
            tap("Navigate up")
            find("Sales", scroll=True)
            tap("Navigate up")
            tap("android:id/search_src_text")
            adb("shell", "input", "text", "zzzzunknown")
            adb("shell", "input", "keyevent", "KEYCODE_ENTER")
            find("No matching features")
            print(f"Passed workspace{suffix}: catalog/model checks, domain drill-down, 48dp rows, browser origin, native time off/settings, search, rotation, Back/Up.")
            return
        if args.time_off:
            activity = "dev.tuist.atlas.preview/dev.tuist.atlas.preview.TimeOffPreviewActivity"
            adb("shell", "am", "start", "-n", activity)
            find("Edit request", scroll=True)
            minimum_target("Edit request")
            minimum_target("Cancel holiday")
            screenshot("android-time-off-overview")
            tap("Edit request")
            find("First day away: 2027-06-07", scroll=True)
            find("Last day away: 2027-06-11", scroll=True)
            screenshot("android-time-off-edit")
            tap("First day away: 2027-06-07")
            assert any(node.get("class") == "android.widget.DatePicker" for node in hierarchy().iter("node"))
            screenshot("android-time-off-date-picker")
            tap("OK")
            tap("Save changes")
            find("Edit request", scroll=True)
            swipe(False)
            tap("Request holiday", clickable=True)
            date_labels = [node.get("text") for node in hierarchy().iter("node") if "day away:" in node.get("text", "")]
            assert len(date_labels) == 2
            adb("shell", "settings", "put", "system", "user_rotation", "0" if args.landscape else "1")
            for label in date_labels:
                find(label, scroll=True)
            adb("shell", "settings", "put", "system", "user_rotation", "1" if args.landscape else "0")
            screenshot("android-time-off-request")
            tap("Request holiday", clickable=True)
            find("Edit request", scroll=True)
            tap("Cancel holiday")
            find("Cancel this holiday?")
            tap("Cancel holiday", clickable=True)
            for _ in range(3):
                swipe(False)
            find("Cancelled", scroll=True)
            screenshot("android-time-off-cancelled")
            adb("shell", "am", "force-stop", "dev.tuist.atlas.preview")
            adb("shell", "am", "start", "-n", activity, "--ez", "fail-save", "true")
            tap("Edit request")
            tap("Save changes")
            swipe(False)
            find("Preview save failed. Your dates are still here.", scroll=True)
            find("First day away: 2027-06-07", scroll=True)
            screenshot("android-time-off-failed-save")
            adb("shell", "input", "keyevent", "KEYCODE_BACK")
            find("Edit request", scroll=True)
            tap("Edit request")
            tap("Navigate up")
            find("Edit request", scroll=True)
            print(f"Passed time off{suffix}: model checks, 48dp controls, native dates, edit/create/cancel, rotation, failed-save retention, Back/Up.")
            return
        adb("shell", "am", "start", "-n", "dev.tuist.atlas.preview/dev.tuist.atlas.preview.SettingsPreviewActivity", "--ez", "model-checks", "true")
        find("Settings")
        find("Not connected", scroll=True)
        screenshot("android-settings")
        tap("Claude")
        field, tree = find("Paste subscription token")
        assert field.get("password") == "true", "Claude entry must be secure"
        find("Subscription token")
        minimum_target("Save connection")
        screenshot("android-claude")
        tap("Paste subscription token")
        adb("shell", "input", "text", "preview-only")
        screenshot("android-claude-keyboard")
        tap("Navigate up")
        find("Settings")
        tap("Claude")
        tap("Save connection")
        find("Paste subscription token", scroll=True)
        tap("Navigate up")
        tap("ChatGPT")
        tap("Sign in with ChatGPT")
        find("DEMO-CODE")
        minimum_target("Cancel sign-in")
        screenshot("android-chatgpt")
        adb("shell", "settings", "put", "system", "user_rotation", "0" if args.landscape else "1")
        find("DEMO-CODE", scroll=True)
        adb("shell", "settings", "put", "system", "user_rotation", "1" if args.landscape else "0")
        find("DEMO-CODE", scroll=True)
        for _ in range(8):
            node, _ = find("Cancel sign-in", scroll=True)
            if node.get("focused") == "true":
                break
            adb("shell", "input", "keyevent", "KEYCODE_TAB")
        assert find("Cancel sign-in")[0].get("focused") == "true", "Cancel must support keyboard focus"
        time.sleep(6)
        assert find("Cancel sign-in")[0].get("focused") == "true", "Background polling must not rebuild focused controls"
        tap("Cancel sign-in")
        find("Sign in with ChatGPT", scroll=True)
        assert not any(node.get("text") == "DEMO-CODE" for node in hierarchy().iter("node"))
        tap("Sign in with ChatGPT")
        find("DEMO-CODE")
        adb("shell", "input", "keyevent", "KEYCODE_BACK")
        find("Settings")
        tap("ChatGPT")
        find("Sign in with ChatGPT", scroll=True)
        tap("Navigate up")
        find("Settings")
        print(f"Passed{suffix}: secure entry/clearing, 48dp targets, keyboard focus across polling, rotation continuity, cancellation, system Back and Up.")
    finally:
        for name, value in original.items():
            if value == "null":
                adb("shell", "settings", "delete", "system", name, capture=True)
            else:
                adb("shell", "settings", "put", "system", name, value)
        if night in ("yes", "no", "auto", "custom"):
            adb("shell", "cmd", "uimode", "night", night, capture=True)


if __name__ == "__main__":
    main()
