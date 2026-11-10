#!/usr/bin/env python3
"""Check reviewed source/bundle consistency without downloading a compiler."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
FILES = ["App.tsx", "nsh.json", "assets/nsh/bundle.js", "assets/nsh/app.json", "assets/nsh/capabilities.json", "assets/nsh/NSH-LICENSE.txt"]


def verify(record=False):
    hashes = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in FILES}
    manifest = ROOT / "bundle.json"
    if record:
        manifest.write_text(json.dumps({"runtime": "0.2.0", "sha256": hashes}, indent=2) + "\n")
    expected = json.loads(manifest.read_text())
    if expected != {"runtime": "0.2.0", "sha256": hashes}:
        raise ValueError("Card source or bundle changed: regenerate with NSH 0.2.0 using cards/build.sh")
    if set(path.name for path in (ROOT / "assets/nsh").iterdir()) != {Path(name).name for name in FILES if name.startswith("assets/")}:
        raise ValueError("Only the reviewed source bundle and metadata may ship, not bytecode or downloaded packages")
    if json.loads((ROOT / "nsh.json").read_text())["capabilities"] != {}:
        raise ValueError("Thread cards must declare no external capabilities")
    denied = {"network": {"hosts": [], "http": []}, "process": {"execute": [], "exit": False, "env": []},
              "fs": {"read": [], "write": []}, "statusBar": False, "clipboard": False}
    if json.loads((ROOT / "assets/nsh/capabilities.json").read_text()) != denied:
        raise ValueError("Generated capabilities must also deny all external access")
    return expected


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--record", action="store_true")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = verify(args.record)
    if args.output:
        args.output.write_text(json.dumps(result) + "\n")
    print("NSH thread card source and bundle verified")
