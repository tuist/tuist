#!/usr/bin/env python3
"""Compares the filesystem of our controller image with the official one.

    compare-layout.py OFFICIAL.tar OURS.tar

Both arguments are `docker export` archives. Prints a Markdown report and exits
1 when a path the controller relies on is missing from ours or differs in type,
mode, owner, symlink target, or file capabilities. Other differences (Alpine
package versions, extra libraries) are listed but do not fail.
"""

import hashlib
import sys
import tarfile

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
    official, ours = manifest(sys.argv[1]), manifest(sys.argv[2])
    failures, notes = [], []

    for path in sorted(official):
        theirs = official[path]
        mine = ours.get(path)
        if mine is None:
            (failures if in_contract(path) else notes).append(f"missing `{path}` ({theirs['type']})")
            continue
        for key in ("type", "mode", "owner", "link", "caps"):
            if theirs[key] != mine[key]:
                line = f"`{path}` {key}: official {theirs[key]}, ours {mine[key]}"
                (failures if in_contract(path) else notes).append(line)
        if theirs["sha256"] and mine["sha256"] and theirs["sha256"] != mine["sha256"]:
            notes.append(f"`{path}` content differs from the official image")

    extra = sorted(set(ours) - set(official))
    capped = sorted(p for p, e in official.items() if e["caps"])

    print("### Filesystem compared with the official controller image\n")
    print(f"- Official: {len(official)} paths, ours: {len(ours)} paths, {len(extra)} only in ours.")
    print(f"- Paths with file capabilities in the official image: {', '.join(f'`{p}`' for p in capped) or 'none'}.")
    print(f"- Contract differences (fail): {len(failures)}. Other differences: {len(notes)}.\n")
    for title, lines in (("Contract differences", failures), ("Other differences", notes),
                         ("Only in ours", [f"`{p}`" for p in extra])):
        if lines:
            print(f"<details><summary>{title} ({len(lines)})</summary>\n")
            for line in lines:
                print(f"- {line}")
            print("\n</details>\n")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
