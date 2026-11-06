#!/usr/bin/env python3
"""Lock and materialize the official Firebase SDK without Gradle.

The resolver deliberately supports the published fixed-version Android POM subset,
not arbitrary Maven projects. Unsupported parents/properties/ranges fail closed.
Normal builds use only the checked-in lock and verify every artifact's digest.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import shutil
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[2]
LOCK = Path(__file__).with_name("dependencies.lock.json")
VENDOR = ROOT / ".once/vendor-maven"
REPOSITORIES = ["https://dl.google.com/dl/android/maven2", "https://repo.maven.apache.org/maven2"]
NAMESPACE = {"m": "http://maven.apache.org/POM/4.0.0"}
EXCLUDED = {"org.jetbrains.kotlin:kotlin-stdlib", "org.jetbrains.kotlin:kotlin-stdlib-common",
            "org.jetbrains.kotlin:kotlin-stdlib-jdk7", "org.jetbrains.kotlin:kotlin-stdlib-jdk8"}


def fetch(url):
    with urllib.request.urlopen(url, timeout=60) as response:
        data = response.read(64 * 1024 * 1024 + 1)
    if len(data) > 64 * 1024 * 1024:
        raise ValueError("Oversized Maven artifact")
    return data


def remote(group, artifact, version, extension):
    suffix = f"{group.replace('.', '/')}/{artifact}/{version}/{artifact}-{version}.{extension}"
    for repository in REPOSITORIES:
        url = f"{repository}/{suffix}"
        try:
            return url, fetch(url)
        except urllib.error.HTTPError as error:
            if error.code != 404:
                raise
    raise ValueError(f"Artifact not found: {suffix}")


def fixed_version(value):
    # Google's POMs use both bare fixed versions and exact [version] constraints.
    value = value.strip()
    if re.fullmatch(r"\[[0-9A-Za-z_.-]+\]", value):
        value = value[1:-1]
    if not re.fullmatch(r"[0-9][0-9A-Za-z_.-]*", value):
        raise ValueError(f"Unsupported version constraint: {value}")
    return value


def version_key(value):
    return tuple((0, int(part)) if part.isdigit() else (1, part)
                 for part in re.split(r"[.-]", value))


def generate_lock():
    selected = {"com.google.firebase:firebase-messaging": "24.1.0"}
    models = {}
    while True:
        previous = dict(selected)
        for coordinate, version in list(selected.items()):
            group, artifact = coordinate.split(":")
            key = (coordinate, version)
            if key not in models:
                _, pom = remote(group, artifact, version, "pom")
                model = ET.fromstring(pom)
                dependencies = []
                for dependency in model.findall("m:dependencies/m:dependency", NAMESPACE):
                    def text(name, default=""):
                        return dependency.findtext(f"m:{name}", default=default, namespaces=NAMESPACE)
                    if text("scope", "compile") not in ("compile", "runtime") or text("optional") == "true":
                        continue
                    name = f"{text('groupId')}:{text('artifactId')}"
                    if name in EXCLUDED:
                        continue
                    dependencies.append((name, fixed_version(text("version"))))
                packaging = model.findtext("m:packaging", default="jar", namespaces=NAMESPACE)
                if packaging not in ("jar", "aar"):
                    raise ValueError(f"Unsupported packaging: {coordinate} {packaging}")
                models[key] = (packaging, dependencies)
            for name, wanted in models[key][1]:
                if name not in selected or version_key(wanted) > version_key(selected[name]):
                    selected[name] = wanted
        if selected == previous:
            break
    artifacts = []
    for coordinate, version in sorted(selected.items()):
        group, artifact = coordinate.split(":")
        packaging, dependencies = models[(coordinate, version)]
        url, data = remote(group, artifact, version, packaging)
        artifacts.append({"coordinate": coordinate, "version": version, "packaging": packaging,
                          "url": url, "sha256": hashlib.sha256(data).hexdigest(),
                          "dependencies": sorted(name for name, _ in dependencies)})
        destination = VENDOR / "downloads" / f"{artifact}-{version}.{packaging}"
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
    LOCK.write_text(json.dumps({"schema_version": 1, "root": "com.google.firebase:firebase-messaging:24.1.0",
                                "excluded_toolchain_artifacts": sorted(EXCLUDED), "artifacts": artifacts}, indent=2) + "\n")
    print(f"Locked {len(artifacts)} artifacts in {LOCK.relative_to(ROOT)}")


def prepare():
    lock = json.loads(LOCK.read_text())
    if lock["schema_version"] != 1:
        raise ValueError("Unsupported Firebase dependency lock")
    # Cargo vendoring uses a different directory. Never leave stale SDK files after a lock update.
    if VENDOR.exists():
        for path in VENDOR.iterdir():
            if path.is_dir() and path.name != "downloads":
                shutil.rmtree(path)
    index = []
    for artifact in lock["artifacts"]:
        name = artifact["coordinate"].split(":")[1]
        version = artifact["version"]
        packaging = artifact["packaging"]
        download = VENDOR / "downloads" / f"{name}-{version}.{packaging}"
        if not download.exists():
            download.parent.mkdir(parents=True, exist_ok=True)
            download.write_bytes(fetch(artifact["url"]))
        data = download.read_bytes()
        if hashlib.sha256(data).hexdigest() != artifact["sha256"]:
            raise ValueError(f"Integrity check failed for {name}; remove {download} and retry")
        target = VENDOR / name
        target.mkdir(parents=True, exist_ok=True)
        (target / "res").mkdir(exist_ok=True)
        if packaging == "jar":
            (target / "classes.jar").write_bytes(data)
            continue
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            for entry in archive.infolist():
                path = Path(entry.filename)
                if path.is_absolute() or ".." in path.parts:
                    raise ValueError("Unsafe AAR path")
                if not entry.is_dir() and entry.filename.startswith(("jni/", "assets/")):
                    raise ValueError(f"Unsupported AAR native libraries/assets: {name}; extend the importer before upgrading")
                if entry.filename.startswith("res/") or entry.filename in ("AndroidManifest.xml", "R.txt"):
                    if not entry.is_dir():
                        output = target / path
                        output.parent.mkdir(parents=True, exist_ok=True)
                        output.write_bytes(archive.read(entry))
            jars = [entry for entry in archive.namelist() if entry == "classes.jar" or
                    (entry.startswith("libs/") and entry.endswith(".jar"))]
            seen = set()
            with zipfile.ZipFile(target / "classes.jar", "w", zipfile.ZIP_DEFLATED) as merged:
                for jar in jars:
                    with zipfile.ZipFile(io.BytesIO(archive.read(jar))) as source:
                        for entry in source.infolist():
                            if entry.is_dir() or entry.filename.startswith("META-INF/"):
                                continue
                            if entry.filename in seen:
                                raise ValueError(f"Duplicate AAR class: {entry.filename}")
                            seen.add(entry.filename)
                            merged.writestr(entry.filename, source.read(entry))
        manifest = ET.parse(target / "AndroidManifest.xml").getroot()
        index.append({"artifact": name, "package": manifest.attrib.get("package", "")})
    (VENDOR / "index.json").write_text(json.dumps(index, indent=2) + "\n")
    print(f"Verified and materialized {len(lock['artifacts'])} Firebase dependencies")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["lock", "prepare"])
    action = parser.parse_args().action
    if action == "lock":
        generate_lock()
    prepare()
