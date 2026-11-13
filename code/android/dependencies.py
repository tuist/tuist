#!/usr/bin/env python3
"""Materialize the pinned Browser POM closure and link its Android resources without Gradle."""

import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
LOCK = Path(__file__).with_name("dependencies.lock.json")
VENDOR = ROOT / ".once/vendor-browser"
PACKAGE = "dev.tuist.code"
REPOSITORIES = ("https://dl.google.com/dl/android/maven2", "https://repo.maven.apache.org/maven2")
EXCLUDED = {"org.jetbrains.kotlin:kotlin-stdlib", "org.jetbrains.kotlin:kotlin-stdlib-common",
            "org.jetbrains.kotlin:kotlin-stdlib-jdk7", "org.jetbrains.kotlin:kotlin-stdlib-jdk8"}
MAX_BYTES = 64 * 1024 * 1024


def normalized(coordinate):
    if not re.fullmatch(r"[a-zA-Z0-9_.-]+:[a-zA-Z0-9_.-]+", coordinate):
        raise ValueError(f"Invalid Maven coordinate: {coordinate}")
    return coordinate.replace(":", "-")


def load_lock():
    lock = json.loads(LOCK.read_text())
    if lock["schema_version"] != 1 or lock["root"] != "androidx.browser:browser:1.9.0":
        raise ValueError("Unsupported Browser dependency lock")
    if set(lock["excluded_toolchain_artifacts"]) != EXCLUDED:
        raise ValueError("Kotlin stdlib must come only from the pinned compiler")
    artifacts = lock["artifacts"]
    names = set()
    directories = set()
    for artifact in artifacts:
        coordinate = artifact["coordinate"]
        name = normalized(coordinate)
        if coordinate in names or name in directories or coordinate in EXCLUDED:
            raise ValueError(f"Duplicate/excluded artifact: {coordinate}")
        names.add(coordinate)
        directories.add(name)
        version = artifact["version"]
        if not re.fullmatch(r"[0-9][0-9A-Za-z_.-]*", version) or ".." in version:
            raise ValueError("Invalid fixed artifact version")
        packaging = artifact["packaging"]
        if packaging not in ("aar", "jar") or not re.fullmatch(r"[0-9a-f]{64}", artifact["sha256"]):
            raise ValueError("Invalid artifact packaging/digest")
        group, module = coordinate.split(":")
        suffix = f"/{group.replace('.', '/')}/{module}/{version}/{module}-{version}.{packaging}"
        if artifact["url"] not in [repo + suffix for repo in REPOSITORIES]:
            raise ValueError(f"Unexpected artifact URL: {coordinate}")
    by_name = {artifact["coordinate"]: artifact for artifact in artifacts}
    if by_name.get("androidx.browser:browser", {}).get("version") != "1.9.0":
        raise ValueError("Missing Browser 1.9.0")
    reachable = set()

    def visit(coordinate):
        if coordinate in reachable:
            return
        if coordinate not in by_name:
            raise ValueError(f"Missing locked dependency: {coordinate}")
        reachable.add(coordinate)
        for dependency in by_name[coordinate]["dependencies"]:
            visit(dependency["coordinate"])

    visit("androidx.browser:browser")
    if reachable != names:
        raise ValueError("Lock includes unreachable artifacts")
    return artifacts


def fetch(url):
    with urllib.request.urlopen(url, timeout=60) as response:
        if not any(response.url.startswith(repo + "/") for repo in REPOSITORIES):
            raise ValueError("Maven download redirected outside the pinned repositories")
        data = response.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        raise ValueError("Oversized Maven artifact")
    return data


def verified_bytes(artifact):
    download = VENDOR / "downloads" / f"{normalized(artifact['coordinate'])}-{artifact['version']}.{artifact['packaging']}"
    if download.is_symlink():
        raise ValueError("Symlink in artifact cache")
    if download.exists():
        if download.stat().st_size > MAX_BYTES:
            raise ValueError("Oversized cached artifact")
        data = download.read_bytes()
    else:
        data = fetch(artifact["url"])
    if hashlib.sha256(data).hexdigest() != artifact["sha256"]:
        raise ValueError(f"Integrity check failed: {artifact['coordinate']}; remove {download} before retrying")
    if not download.exists():
        download.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=download.parent, delete=False) as temporary:
            temporary.write(data)
            path = Path(temporary.name)
        path.replace(download)
    return data


def checked_entries(archive):
    entries = archive.infolist()
    if len(entries) > 30000 or sum(entry.file_size for entry in entries) > 128 * 1024 * 1024:
        raise ValueError("Oversized ZIP contents")
    seen = set()
    for entry in entries:
        name = entry.filename
        path = PurePosixPath(name)
        if (not name or path.is_absolute() or ".." in path.parts or "\\" in name or ":" in name
                or str(path) != name.rstrip("/") or name in seen
                or stat.S_ISLNK(entry.external_attr >> 16)):
            raise ValueError(f"Unsafe/duplicate ZIP path: {name}")
        seen.add(name)
    return entries


def merged_jar(archive, target):
    contents = {}
    jars = sorted(entry.filename for entry in archive.infolist()
                  if entry.filename == "classes.jar" or (entry.filename.startswith("libs/") and entry.filename.endswith(".jar")))
    if not jars:
        raise ValueError("AAR has no classes jar")
    for name in jars:
        with zipfile.ZipFile(io.BytesIO(archive.read(name))) as source:
            for entry in checked_entries(source):
                path = entry.filename
                if entry.is_dir() or re.fullmatch(r"META-INF/(?:MANIFEST\.MF|[^/]+\.(?:SF|RSA|DSA|EC))", path, re.IGNORECASE):
                    continue
                data = source.read(entry)
                if path in contents:
                    if path.startswith("META-INF/services/"):
                        contents[path] = b"\n".join(sorted(set(contents[path].splitlines() + data.splitlines()))) + b"\n"
                        continue
                    raise ValueError(f"Duplicate AAR jar entry: {path}")
                contents[path] = data
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as output:
        for name, data in sorted(contents.items()):
            entry = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            output.writestr(entry, data)


def materialize(artifact, data, target):
    target.mkdir()
    (target / "res").mkdir()
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        entries = checked_entries(archive)
        if artifact["packaging"] == "jar":
            (target / "classes.jar").write_bytes(data)
            return None
        for entry in entries:
            if entry.is_dir():
                continue
            if entry.filename.startswith(("jni/", "assets/", "prefab/")):
                raise ValueError("AAR native libraries/assets require an explicit importer upgrade")
            if entry.filename.startswith("res/") or entry.filename in ("AndroidManifest.xml", "R.txt"):
                output = target / entry.filename
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_bytes(archive.read(entry))
        manifest = ET.parse(target / "AndroidManifest.xml").getroot()
        package = manifest.attrib.get("package", "")
        if not re.fullmatch(r"[a-zA-Z_][\w]*(?:\.[a-zA-Z_][\w]*)+", package):
            raise ValueError("Missing/invalid AAR package")
        merged_jar(archive, target / "classes.jar")
        return package


def prepare():
    artifacts = load_lock()
    VENDOR.mkdir(parents=True, exist_ok=True)
    index = []
    with tempfile.TemporaryDirectory(prefix=".prepare-", dir=VENDOR) as temporary:
        staging = Path(temporary)
        classes = set()
        for artifact in artifacts:
            name = normalized(artifact["coordinate"])
            target = staging / name
            package = materialize(artifact, verified_bytes(artifact), target)
            with zipfile.ZipFile(target / "classes.jar") as archive:
                for entry in archive.namelist():
                    if entry.endswith(".class") and not entry.endswith("module-info.class"):
                        if entry in classes:
                            raise ValueError(f"Duplicate dependency class: {entry}")
                        classes.add(entry)
            index.append({"coordinate": artifact["coordinate"], "version": artifact["version"],
                          "directory": name, "package": package, "sha256": artifact["sha256"]})
        for item in index:
            target = VENDOR / item["directory"]
            if target.is_symlink():
                raise ValueError("Symlink in prepared dependencies")
            if target.exists():
                shutil.rmtree(target)
            (staging / item["directory"]).replace(target)
        current = {item["directory"] for item in index}
        for path in VENDOR.iterdir():
            if path.is_dir() and path.name not in current | {"downloads", staging.name} and not path.name.startswith("."):
                if path.is_symlink():
                    raise ValueError("Symlink in prepared dependencies")
                shutil.rmtree(path)
        (VENDOR / "index.json").write_text(json.dumps(index, indent=2) + "\n")
    print(f"Verified and prepared {len(index)} Browser dependencies ({len(classes)} unique classes)")


def run(*command):
    subprocess.run([str(part) for part in command], check=True)


def build(arguments):
    if len(arguments) < 9 or (len(arguments) - 7) % 2:
        raise ValueError("build requires aapt2 android.jar javac jar r.jar R.txt resources.apk and manifest/compiled.zip pairs")
    aapt2, android_jar, javac, jar, r_jar, r_txt, linked, *libraries = arguments
    packages, compiled = [], []
    for manifest, output in zip(libraries[::2], libraries[1::2]):
        source = Path(manifest)
        package = ET.parse(source).getroot().attrib.get("package")
        if not package or not re.fullmatch(r"[a-zA-Z_][\w]*(?:\.[a-zA-Z_][\w]*)+", package):
            raise ValueError("Invalid library resource namespace")
        packages.append(package)
        resources = source.parent / "res"
        Path(output).parent.mkdir(parents=True, exist_ok=True)
        if any(path.is_file() for path in resources.rglob("*")):
            run(aapt2, "compile", "--dir", resources, "-o", output)
        else:
            with zipfile.ZipFile(output, "w"):
                pass
        compiled.append(output)
    for output in (r_jar, r_txt, linked):
        Path(output).parent.mkdir(parents=True, exist_ok=True)
    VENDOR.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".r-", dir=VENDOR) as temporary:
        root = Path(temporary)
        own = root / "app.zip"
        run(aapt2, "compile", "--dir", ROOT / "android/res", "-o", own)
        command = [aapt2, "link", "--manifest", str(ROOT / "android/AndroidManifest.xml"), "-I", android_jar,
                   "--java", str(root / "r"), "--output-text-symbols", r_txt,
                   "--min-sdk-version", "26", "--target-sdk-version", "35", "--auto-add-overlay",
                   "--custom-package", PACKAGE, "--version-code", "1", "--version-name", "0.1.0",
                   "--extra-packages", ":".join(sorted(set(packages))), "-o", linked]
        # Match Once: application first, then provider resource zips in the supplied order.
        for archive in [str(own)] + compiled:
            command.extend(["-R", archive])
        run(*command)
        app_package = root / "r" / PACKAGE.replace(".", "/")
        sources = sorted(path for path in (root / "r").rglob("R.java") if path.parent != app_package)
        if not sources:
            raise ValueError("No library R classes generated")
        source_list = root / "sources.txt"
        source_list.write_text("\n".join('"' + str(path) + '"' for path in sources))
        classes = root / "classes"
        classes.mkdir()
        run(javac, "-source", "8", "-target", "8", "-classpath", android_jar, "-d", classes, f"@{source_list}")
        run(jar, "cf", r_jar, "-C", classes, ".")


def verify(arguments):
    if len(arguments) != 3:
        raise ValueError("verify requires aapt2 R.txt apk")
    aapt2, r_txt, apk = arguments
    dump = subprocess.check_output([aapt2, "dump", "resources", apk], text=True)
    actual = {}
    for resource_id, resource_type, name in re.findall(
            r"resource (0x[0-9a-fA-F]+) (?:[\w.]+:)?([\w]+)/([\w.]+)", dump):
        actual.setdefault((resource_type, name.replace(".", "_")), set()).add(int(resource_id, 16))
    checked = 0
    for line in Path(r_txt).read_text().splitlines():
        match = re.fullmatch(r"int (\w+) (\w+) (0x[0-9a-fA-F]+)", line)
        if not match or match[1] == "styleable":
            continue
        expected = int(match[3], 16)
        if expected >> 24 != 0x7F:
            continue
        if actual.get((match[1], match[2])) != {expected}:
            raise ValueError(f"Browser R resource mismatch: {match[1]}/{match[2]}")
        checked += 1
    if checked == 0:
        raise ValueError("No APK resource IDs verified")
    print(f"Verified {checked} Browser/app resource IDs against the final APK")


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in ("prepare", "build", "verify"):
        sys.exit("Usage: dependencies.py prepare | build <tools/outputs/library pairs> | verify <aapt2> <R.txt> <apk>")
    if sys.argv[1] == "prepare":
        if len(sys.argv) != 2:
            sys.exit("prepare takes no arguments")
        prepare()
    else:
        {"build": build, "verify": verify}[sys.argv[1]](sys.argv[2:])
