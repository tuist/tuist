#!/usr/bin/env python3
"""Plan a macOS-only patch from an immutable source and the live Sparkle feed."""

import argparse
import re
import subprocess
import time
import xml.etree.ElementTree as ET


def git(*args):
    return subprocess.check_output(["git", *args], text=True).strip()


def plan(stable_tag, source_sha, appcast, build_number):
    match = re.fullmatch(r"app@(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", stable_tag)
    if not match or not re.fullmatch(r"[0-9a-f]{40}", source_sha):
        raise ValueError("Use an exact app@X.Y.Z stable tag and a full lowercase source SHA")
    base = git("rev-parse", "--verify", f"refs/tags/{stable_tag}^{{commit}}")
    if git("rev-parse", "--verify", f"{source_sha}^{{commit}}") != source_sha:
        raise ValueError("Source must identify a commit")
    subprocess.run(["git", "merge-base", "--is-ancestor", base, source_sha], check=True)
    if source_sha == base:
        raise ValueError("Source contains no hotfix")

    version = tuple(map(int, match.groups()))
    next_version = f"{version[0]}.{version[1]}.{version[2] + 1}"
    if git("tag", "--list", f"app@{next_version}"):
        raise ValueError("Next patch tag already exists; recover the original release instead")

    namespace = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
    items = ET.parse(appcast).getroot().findall("./channel/item")
    if not items:
        raise ValueError("Live feed is empty")
    versions = [tuple(map(int, item.findtext(f"{namespace}shortVersionString").split("."))) for item in items]
    newest = items[versions.index(max(versions))]
    if max(versions) != version:
        raise ValueError("Stable tag does not match the newest live Sparkle version")
    enclosure = newest.find("enclosure")
    expected_url = f"https://github.com/tuist/tuist/releases/download/{stable_tag}/Tuist.dmg"
    if enclosure is None or enclosure.get("url") != expected_url:
        raise ValueError("Live feed does not identify the stable tag DMG")
    builds = [item.findtext(f"{namespace}version", "") for item in items]
    if not newest.findtext(f"{namespace}version", "").isdecimal():
        raise ValueError("Newest live build number is not numeric")
    if build_number <= max(int(value) for value in builds if value.isdecimal()):
        raise ValueError("Hotfix build must exceed every live Sparkle build")
    return {
        "app-should-release": "true",
        "app-next-version": f"app@{next_version}",
        "app-next-version-number": next_version,
        "source-sha": source_sha,
        "build-number": str(build_number),
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stable_tag")
    parser.add_argument("source_sha")
    parser.add_argument("appcast")
    args = parser.parse_args()
    try:
        outputs = plan(args.stable_tag, args.source_sha, args.appcast, int(time.time()))
    except (ValueError, TypeError, AttributeError, ET.ParseError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Cannot plan macOS hotfix: {error}\n")
    for key, value in outputs.items():
        print(f"{key}={value}")
