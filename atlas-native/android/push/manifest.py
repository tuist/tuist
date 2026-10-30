#!/usr/bin/env python3
"""Fail if a pinned SDK introduces an unreviewed manifest requirement."""
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
ANDROID = "{http://schemas.android.com/apk/res/android}"
TOOLS = "{http://schemas.android.com/tools}"
EXCLUDED = {
    # Explicit FirebaseOptions initialization lives in AtlasApplication, before services run.
    ("provider", "com.google.firebase.provider.FirebaseInitProvider"),
    # The app's subclass handles only authenticated, locally enabled data notifications.
    ("service", "com.google.firebase.messaging.FirebaseMessagingService"),
}


def identity(node):
    return node.tag, node.attrib.get(ANDROID + "name", "")


def require_subset(required, actual):
    for attribute, value in required.attrib.items():
        if attribute.startswith(TOOLS):
            continue
        if actual.attrib.get(attribute) != value:
            raise ValueError(f"SDK manifest mismatch: {identity(required)} {attribute}")
    for child in required:
        candidates = [item for item in actual if identity(item) == identity(child)]
        if len(candidates) != 1:
            raise ValueError(f"Missing/ambiguous SDK manifest child: {identity(child)}")
        require_subset(child, candidates[0])


def audit():
    app = ET.parse(ROOT / "android/AndroidManifest.xml").getroot()
    application = app.find("application")
    count = 0
    manifests = sorted((ROOT / ".once/vendor-maven").glob("*/AndroidManifest.xml"))
    if not manifests:
        raise ValueError("Run prepare:android before the manifest audit")
    for manifest in manifests:
        library = ET.parse(manifest).getroot()
        for node in library:
            if node.tag == "uses-sdk":
                if int(node.attrib.get(ANDROID + "minSdkVersion", "1")) > 26:
                    raise ValueError(f"SDK raises minimum Android version: {manifest}")
                continue
            required = list(node) if node.tag == "application" else [node]
            parent = application if node.tag == "application" else app
            for child in required:
                if identity(child) in EXCLUDED:
                    continue
                candidates = [item for item in parent if identity(item) == identity(child)]
                if len(candidates) != 1:
                    raise ValueError(f"Unreviewed SDK manifest requirement: {manifest}: {identity(child)}")
                require_subset(child, candidates[0])
                count += 1
    print(f"Audited {count} Firebase SDK manifest requirements")


if __name__ == "__main__":
    audit()
