#!/usr/bin/env python3
# Experiment: estimate how much of a Tart disk changes between two images
# without pushing them. Hashes disk.img in fixed 512 MiB chunks (the size the
# tart-push action uploads) and compares chunks at the same offsets; a host
# that holds the old image would pull roughly the changed, non-zero chunks.
#   chunks.py hash <disk.img> <out>
#   chunks.py diff <old.hashes> <new.hashes> <label>
import hashlib
import sys

CHUNK = 512 * 1024 * 1024
ZERO = hashlib.sha1(bytes(CHUNK)).hexdigest()


def hash_disk(path, out):
    with open(path, "rb") as f, open(out, "w") as o:
        while True:
            data = f.read(CHUNK)
            if not data:
                break
            h = hashlib.sha1(data).hexdigest()
            if len(data) < CHUNK and not any(data):
                h = ZERO
            o.write(h + "\n")


def diff(old, new, label):
    a = open(old).read().split()
    b = open(new).read().split()
    gb = CHUNK / 1e9
    nonzero_new = [i for i, h in enumerate(b) if h != ZERO]
    changed = [i for i in nonzero_new if i >= len(a) or a[i] != b[i]]
    print(
        f"BUNDLE-EXP DELTA {label}: new image {len(nonzero_new) * gb:.1f} GB non-zero, "
        f"changed {len(changed) * gb:.1f} GB ({len(changed)} of {len(nonzero_new)} chunks), "
        f"kept {(len(nonzero_new) - len(changed)) * gb:.1f} GB"
    )


if __name__ == "__main__":
    if sys.argv[1] == "hash":
        hash_disk(sys.argv[2], sys.argv[3])
    else:
        diff(sys.argv[2], sys.argv[3], sys.argv[4])
