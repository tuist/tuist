"""Select only the signed APK, never ApkInfo's signing keys or deploy JAR."""

import os
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path


def sdk_tool(name, override):
    if override:
        return override
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if sdk:
        tools = Path(sdk) / (
            "cmdline-tools" if name == "apkanalyzer" else "build-tools"
        )
        versions = sorted(
            (
                path
                for path in tools.glob("*")
                if re.fullmatch(r"\d+(\.\d+)*", path.name)
            ),
            key=lambda path: tuple(int(part) for part in path.name.split(".")),
            reverse=True,
        )
        if name == "apkanalyzer":
            versions.insert(0, tools / "latest")
        for version in versions:
            tool = version / "bin" / name if name == "apkanalyzer" else version / name
            if tool.is_file():
                return str(tool)
    found = shutil.which(name)
    if not found:
        raise ValueError(f"Set ANDROID_HOME or provide --{name} to verify the APK")
    return found


def prepare(apk, directory, args):
    verification = subprocess.run(
        [sdk_tool("apksigner", args.apksigner), "verify", "--print-certs", str(apk)],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    certificates = re.findall(
        r"certificate SHA-256 digest: ([0-9a-fA-F]{64})", verification
    )
    if not certificates:
        raise ValueError("The APK has no verified signing certificate")
    manifest_xml = subprocess.run(
        [sdk_tool("apkanalyzer", args.apkanalyzer), "manifest", "print", str(apk)],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    try:
        manifest = ET.fromstring(manifest_xml)
    except ET.ParseError:
        raise ValueError(
            "Android SDK returned an invalid application manifest"
        ) from None
    if manifest.tag != "manifest" or not manifest.get("package"):
        raise ValueError("The APK has no application ID")
    if manifest.find("instrumentation") is not None:
        raise ValueError("Instrumentation APKs are not application previews")
    android = "{http://schemas.android.com/apk/res/android}"
    return (
        apk,
        "application/vnd.android.package-archive",
        "dev.once.android-install.v1",
        {
            "schema": "once.android_application.v1",
            "application_id": manifest.get("package"),
            "version_code": manifest.get(android + "versionCode"),
            "version_name": manifest.get(android + "versionName"),
            "certificate_sha256": certificates,
            "signature_verified": True,
        },
    )
