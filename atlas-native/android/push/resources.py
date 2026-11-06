#!/usr/bin/env python3
"""Generate AAR R classes and verify their IDs against the final APK before delivery."""
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile


def run(*command):
    subprocess.run([str(part) for part in command], check=True)


def build(arguments):
    aapt2, android_jar, javac, jar, r_jar, r_txt, linked, *libraries = arguments
    packages = []
    compiled = []
    for manifest, output in zip(libraries[::2], libraries[1::2]):
        source = Path(manifest)
        package = ET.parse(source).getroot().attrib.get("package")
        if package:
            packages.append(package)
        resources = source.parent / "res"
        Path(output).parent.mkdir(parents=True, exist_ok=True)
        if list(resources.rglob("*")):
            run(aapt2, "compile", "--dir", resources, "-o", output)
        else:
            with zipfile.ZipFile(output, "w"):
                pass
        compiled.append(output)
    Path(r_jar).parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="atlas-firebase-r-") as temporary:
        root = Path(temporary)
        own = root / "app.zip"
        run(aapt2, "compile", "--dir", "android/res", "-o", own)
        command = [aapt2, "link", "--manifest", "android/AndroidManifest.xml", "-I", android_jar,
                   "--java", str(root / "r"), "--output-text-symbols", r_txt,
                   "--min-sdk-version", "26", "--target-sdk-version", "35", "--auto-add-overlay",
                   "--custom-package", "dev.tuist.atlas", "--version-code", "1", "--version-name", "0.1.0",
                   "--extra-packages", ":".join(sorted(set(packages))), "-o", linked]
        for archive in [str(own)] + compiled:
            command.extend(["-R", archive])
        run(*command)
        sources = sorted(path for path in (root / "r").rglob("R.java")
                         if path.parent != root / "r/dev/tuist/atlas")
        if not sources:
            raise ValueError("No library R classes generated")
        source_list = root / "sources.txt"
        source_list.write_text("\n".join(str(path) for path in sources))
        classes = root / "classes"
        classes.mkdir()
        run(javac, "-source", "8", "-target", "8", "-classpath", android_jar,
            "-d", classes, f"@{source_list}")
        run(jar, "cf", r_jar, "-C", classes, ".")


def verify(arguments):
    aapt2, r_txt, apk = arguments
    dump = subprocess.check_output([aapt2, "dump", "resources", apk], text=True)
    actual = {}
    for resource_id, resource_type, name in re.findall(
            r"resource (0x[0-9a-fA-F]+) (?:[\w.]+:)?([\w]+)/([\w.]+)", dump):
        actual[(resource_type, name)] = int(resource_id, 16)
    checked = 0
    for line in Path(r_txt).read_text().splitlines():
        match = re.fullmatch(r"int (\w+) (\w+) (0x[0-9a-fA-F]+)", line)
        if not match or match[1] == "styleable":
            continue
        expected = int(match[3], 16)
        if expected >> 24 != 0x7F:
            continue
        # aapt2 preserves periods in style names while Java R fields replace them.
        candidates = [value for (kind, name), value in actual.items()
                      if kind == match[1] and name.replace(".", "_") == match[2]]
        if candidates != [expected]:
            raise ValueError(f"Firebase R resource mismatch: {match[1]}/{match[2]}")
        checked += 1
    if checked == 0:
        raise ValueError("No APK resource IDs verified")
    print(f"Verified {checked} Firebase resource IDs against the final APK")


if __name__ == "__main__":
    {"build": build, "verify": verify}[sys.argv[1]](sys.argv[2:])
