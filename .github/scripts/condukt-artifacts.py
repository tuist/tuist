#!/usr/bin/env python3
"""Fail closed unless every supported NIF has exactly one nonempty archive."""

from pathlib import Path
import re
import sys


def expected_artifacts(version):
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("expected a stable semantic version")
    targets = {
        "condukt_bashkit": [
            "aarch64-apple-darwin", "x86_64-apple-darwin",
            "x86_64-unknown-linux-gnu", "aarch64-unknown-linux-gnu",
            "x86_64-pc-windows-msvc",
        ],
        "condukt_microsandbox": [
            "aarch64-apple-darwin", "x86_64-unknown-linux-gnu",
            "aarch64-unknown-linux-gnu",
        ],
    }
    result = set()
    for crate, platforms in targets.items():
        for target in platforms:
            prefix, suffix = ("", "dll") if "windows" in target else ("lib", "so")
            for nif in ("2.16", "2.17"):
                result.add(f"{crate}/{prefix}{crate}-v{version}-nif-{nif}-{target}.{suffix}.tar.gz")
    return result


def validate(version, root):
    expected = expected_artifacts(version)
    actual = {str(path.relative_to(root)) for path in root.rglob("*.tar.gz")}
    if actual != expected:
        raise ValueError(f"NIF matrix mismatch: missing={sorted(expected - actual)}, extra={sorted(actual - expected)}")
    for name in sorted(expected):
        path = root / name
        if path.is_symlink() or not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f"empty or invalid artifact: {path}")
    return [root / name for name in sorted(expected)]


if __name__ == "__main__":
    for artifact in validate(sys.argv[1], Path(sys.argv[2])):
        print(artifact)
