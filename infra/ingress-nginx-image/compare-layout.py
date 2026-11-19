#!/usr/bin/env python3
"""Compares the filesystem of our controller image with a reference image.

    compare-layout.py REFERENCE.tar OURS.tar LABEL

Both archives are `docker export` output; LABEL names the reference in the
report. Prints a Markdown report and exits 1 when a path the reference
controller relies on is missing from ours or differs in type, mode, owner,
symlink target, or file capabilities (contract differences). Other differences
(package versions, extra libraries) are listed as well.
"""

import hashlib
import sys
import tarfile
from collections import defaultdict

# Paths the controller, its chart, and its nginx configuration rely on.
CONTRACT = (
    "nginx-ingress-controller",
    "dbg",
    "wait-shutdown",
    "usr/bin/dumb-init",
    "usr/bin/nginx",
    "sbin/nginx",
    "etc/ld-musl-x86_64.path",
    "etc/nginx/",
    "etc/ingress-controller/",
    "usr/local/nginx/",
    "usr/local/lib/lua/",
    "usr/local/share/lua/",
    "usr/local/share/luajit-2.1.0-beta3/",
    "opt/modsecurity/",
    "var/lib/nginx/",
    "var/log/nginx/",
    "var/log/audit/",
    "tmp/nginx/",
)

# Configuration the controller renders and runs; expected byte-identical.
SAME_CONTENT = ("etc/nginx/template/", "etc/nginx/lua/", "etc/nginx/nginx.conf")

TYPES = {
    tarfile.REGTYPE: "file",
    tarfile.AREGTYPE: "file",
    tarfile.DIRTYPE: "dir",
    tarfile.SYMTYPE: "symlink",
    tarfile.LNKTYPE: "hardlink",
    tarfile.CHRTYPE: "char",
    tarfile.BLKTYPE: "block",
    tarfile.FIFOTYPE: "fifo",
}


def in_contract(path):
    return any(path == p.rstrip("/") or (p.endswith("/") and path.startswith(p)) for p in CONTRACT)


def manifest(archive):
    entries = {}
    with tarfile.open(archive, "r|") as tar:
        for member in tar:
            path = member.name.removeprefix("./").rstrip("/")
            if not path:
                continue
            digest = None
            if member.isfile() and path.startswith(SAME_CONTENT):
                digest = hashlib.sha256(tar.extractfile(member).read()).hexdigest()
            entries[path] = {
                "type": TYPES.get(member.type, repr(member.type)),
                "mode": oct(member.mode),
                "owner": f"{member.uid}:{member.gid}",
                "link": member.linkname or None,
                "caps": member.pax_headers.get("SCHILY.xattr.security.capability", "").encode("utf-8", "surrogateescape").hex() or None,
                "sha256": digest,
            }
    return entries


def main():
    official, ours, label = manifest(sys.argv[1]), manifest(sys.argv[2]), sys.argv[3]
    failures, notes = [], []
    # Paths whose only difference is the owner, grouped by (theirs, ours):
    # a different group id repeats on every file the controller ships.
    owners = defaultdict(lambda: ([], []))
    # Missing paths outside the contract (base OS files), counted by directory.
    missing_dirs = defaultdict(int)

    for path in sorted(official):
        theirs = official[path]
        mine = ours.get(path)
        if mine is None:
            if in_contract(path):
                failures.append(f"missing `{path}` ({theirs['type']})")
            else:
                missing_dirs["/".join(path.split("/")[:2])] += 1
            continue
        differs = [key for key in ("type", "mode", "owner", "link", "caps") if theirs[key] != mine[key]]
        if differs == ["owner"]:
            owners[(theirs["owner"], mine["owner"])][0 if in_contract(path) else 1].append(path)
        else:
            for key in differs:
                line = f"`{path}` {key}: theirs {theirs[key]}, ours {mine[key]}"
                (failures if in_contract(path) else notes).append(line)
        if theirs["sha256"] and mine["sha256"] and theirs["sha256"] != mine["sha256"]:
            notes.append(f"`{path}` content differs")
    for (theirs, mine), (contract, other) in sorted(owners.items()):
        for paths, bucket in ((contract, failures), (other, notes)):
            if paths:
                bucket.append(f"{len(paths)} paths differ only in owner: theirs {theirs}, ours {mine} "
                              f"(for example {', '.join(f'`{p}`' for p in paths[:3])})")

    notes[:0] = [f"{n} missing under `{d}`" for d, n in sorted(missing_dirs.items())]
    extra = sorted(set(ours) - set(official))
    extra_dirs = defaultdict(int)
    for p in extra:
        extra_dirs["/".join(p.split("/")[:2])] += 1
    capped = sorted(p for p, e in official.items() if e["caps"])
    ours_capped = sorted(p for p, e in ours.items() if e["caps"])

    print(f"#### Filesystem compared with {label}\n")
    print(f"- Theirs: {len(official)} paths, ours: {len(ours)} paths, {len(extra)} only in ours.")
    print(f"- File capabilities: theirs {', '.join(f'`{p}`' for p in capped) or 'none'}; ours {', '.join(f'`{p}`' for p in ours_capped) or 'none'}.")
    print(f"- Contract differences: {len(failures)}. Other differences: {len(notes)}.\n")
    for title, lines in (("Contract differences", failures), ("Other differences", notes),
                         ("Only in ours, by directory", [f"`{d}`: {n}" for d, n in sorted(extra_dirs.items())])):
        if lines:
            print(f"<details><summary>{title} ({len(lines)})</summary>\n")
            for line in lines:
                print(f"- {line}")
            print("\n</details>\n")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
