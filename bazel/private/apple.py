"""Normalize rules_apple archives to the existing root .app ZIP contract."""

import os
import plistlib
import shutil
import stat
import subprocess
import sys
import zipfile
from pathlib import Path


def extract(archive, directory):
    # Preserve bundle symlinks/modes, but never extract outside the temporary root
    # or follow a previously extracted symlink when writing a later entry.
    directory_modes = {}
    with zipfile.ZipFile(archive) as source:
        if sum(entry.file_size for entry in source.infolist()) > 21_474_836_480:
            raise ValueError("The Apple archive exceeds 20 GiB")
        for entry in source.infolist():
            path = directory / entry.filename
            if Path(entry.filename).is_absolute() or ".." in Path(entry.filename).parts:
                raise ValueError("Unsafe Apple archive path")
            if not path.resolve().is_relative_to(directory.resolve()):
                raise ValueError("Apple archive symlink escapes its root")
            path.parent.mkdir(parents=True, exist_ok=True)
            mode = entry.external_attr >> 16
            if entry.is_dir():
                path.mkdir(exist_ok=True)
                directory_modes[path] = mode & 0o777
            elif stat.S_ISLNK(mode):
                target = source.read(entry).decode("utf-8")
                if (
                    not (path.parent / target)
                    .resolve()
                    .is_relative_to(directory.resolve())
                ):
                    raise ValueError("Apple archive symlink escapes its root")
                path.symlink_to(target)
                if os.chmod in os.supports_follow_symlinks:
                    os.chmod(path, mode & 0o777, follow_symlinks=False)
            else:
                with source.open(entry) as src, path.open("xb") as dst:
                    shutil.copyfileobj(src, dst)
                path.chmod(mode & 0o777)
    # Restore directories last, so read-only directories remain extractable.
    # Implicit parents must not take the publisher's umask into the digest.
    for path in sorted(directory.rglob("*"), key=lambda p: len(p.parts), reverse=True):
        if path.is_dir() and not path.is_symlink():
            path.chmod(directory_modes.get(path, 0o755))


def bundle_zip(bundle, destination):
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(bundle.rglob("*")):
            if not path.resolve().is_relative_to(bundle.resolve()):
                raise ValueError("Application symlink escapes its bundle")
            name = path.relative_to(bundle.parent).as_posix()
            mode = path.lstat().st_mode
            if path.is_dir() and not path.is_symlink():
                name += "/"
            entry = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            entry.create_system = 3
            entry.external_attr = mode << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            if path.is_symlink():
                archive.writestr(entry, os.fsencode(os.readlink(path)))
            elif path.is_dir():
                archive.writestr(entry, b"")
            else:
                with (
                    path.open("rb") as src,
                    archive.open(entry, "w", force_zip64=True) as dst,
                ):
                    shutil.copyfileobj(src, dst)


def prepare(archive, directory, args):
    if sys.platform != "darwin":
        raise ValueError("Apple preview verification requires macOS and codesign")
    unpacked = directory / "unpacked"
    unpacked.mkdir()
    extract(archive, unpacked)
    bundles = list(unpacked.glob("*.app")) + list(unpacked.glob("Payload/*.app"))
    if len(bundles) != 1:
        raise ValueError(
            "Expected exactly one top-level application in the Apple archive"
        )
    bundle = bundles[0]
    plist = bundle / "Info.plist"
    if not plist.is_file():
        plist = bundle / "Contents/Info.plist"
    with plist.open("rb") as stream:
        info = plistlib.load(stream)
    platforms = info.get("CFBundleSupportedPlatforms", [])
    supported = {
        "iPhoneSimulator": ("ios", "simulator"),
        "AppleTVSimulator": ("tvos", "simulator"),
        "WatchSimulator": ("watchos", "simulator"),
        "XRSimulator": ("visionos", "simulator"),
        "MacOSX": ("macos", "device"),
    }
    if len(platforms) != 1 or platforms[0] not in supported:
        raise ValueError(
            "Only simulator and macOS applications are eligible; device archives are not"
        )
    platform, variant = supported[platforms[0]]
    subprocess.run(
        ["/usr/bin/codesign", "--verify", "--deep", "--strict", str(bundle)],
        check=True,
        capture_output=True,
    )
    signature = subprocess.run(
        ["/usr/bin/codesign", "--display", "--verbose=4", str(bundle)],
        check=True,
        capture_output=True,
        text=True,
    )
    if "Signature=adhoc" not in signature.stderr.splitlines():
        raise ValueError("Only verified ad-hoc signed Apple applications are eligible")
    if info.get("CFBundlePackageType") != "APPL" or not info.get("CFBundleIdentifier"):
        raise ValueError("The archive is not an application")
    output = directory / "application.zip"
    bundle_zip(bundle, output)
    return (
        output,
        "application/zip",
        "dev.once.apple-install.v2",
        {
            "schema": "once.apple_application.v1",
            "bundle_identifier": info["CFBundleIdentifier"],
            "display_name": info.get("CFBundleDisplayName") or info.get("CFBundleName"),
            "version": info.get("CFBundleShortVersionString"),
            "build_version": info.get("CFBundleVersion"),
            "platform": platform,
            "sdk_variant": variant,
            "signing": "ad_hoc",
            "signature_verified": True,
        },
    )
