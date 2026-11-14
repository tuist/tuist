#!/usr/bin/env python3
"""Materialize a portable Cargo dependency graph for Once 0.77's native rules.

Only metadata stubs are copied: every compiled first-party source remains in
crates/. Versions/checksums must remain a subset of the authoritative Cargo.lock.
"""
import pathlib
import re
import shutil
import subprocess
import tomllib

ROOT = pathlib.Path(__file__).resolve().parent
DEST = ROOT / "native-dependencies"
PACKAGES = ("core", "oauth", "jwt", "credentials")


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    manifest = (ROOT / "Cargo.toml").read_text()
    manifest, count = re.subn(
        r"^members = .*?$",
        'members = ["crates/core", "crates/oauth", "crates/jwt", "crates/credentials"]',
        manifest,
        count=1,
        flags=re.MULTILINE,
    )
    if count != 1:
        raise SystemExit("Could not identify the Cargo workspace members")
    (DEST / "Cargo.toml").write_text(manifest)
    for package in PACKAGES:
        directory = DEST / "crates" / package
        (directory / "src").mkdir(parents=True, exist_ok=True)
        text = (ROOT / "crates" / package / "Cargo.toml").read_text()
        if package == "oauth":
            # The core disables OAuth's network feature; metadata treats members
            # as roots, so explicitly make the portable selection here as well.
            text = text.replace('default = ["network"]', 'default = []')
        (directory / "Cargo.toml").write_text(text)
        (directory / "src/lib.rs").write_text("// Metadata only; Once compiles the original sources.\n")
    shutil.copyfile(ROOT / "Cargo.lock", DEST / "Cargo.lock")
    subprocess.run(
        ["cargo", "metadata", "--format-version", "1"],
        cwd=DEST, check=True, stdout=subprocess.DEVNULL,
    )
    original = tomllib.loads((ROOT / "Cargo.lock").read_text())["package"]
    resolved = tomllib.loads((DEST / "Cargo.lock").read_text())["package"]
    def identity(package):
        return tuple(package.get(key) for key in ("name", "version", "source", "checksum"))

    locked = {identity(package) for package in original}
    for package in resolved:
        if package.get("source") and identity(package) not in locked:
            raise SystemExit(f"Native dependency drift from Cargo.lock: {package['name']}")
    subprocess.run(
        ["cargo", "vendor", "--locked", "--versioned-dirs", "vendor"],
        cwd=DEST, check=True, stdout=subprocess.DEVNULL,
    )
    print(f"Prepared {len(resolved)} locked native packages; original sources unchanged")


if __name__ == "__main__":
    main()
