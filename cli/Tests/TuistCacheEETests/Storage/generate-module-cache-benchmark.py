"""Create labeled synthetic transfer workloads around real three-SDK XCFrameworks."""

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import random
import shutil
import uuid


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--fixtures", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--repetitions", type=int, default=3)
args = parser.parse_args()
sources = sorted(args.fixtures.rglob("*.xcframework"))
assert sources, "Expected real compiled XCFramework fixtures"
assert args.repetitions > 0
args.output.mkdir(parents=True, exist_ok=False)
run_id = str(uuid.uuid4())
manifest = {"runID": run_id, "repetitions": args.repetitions, "corpora": {}}

# Sizes are per SDK. Mixed payloads alternate random and zero-filled blocks;
# incompressible payloads are all pseudorandom. Neither models Mach-O entropy.
for corpus, count, mebibytes, mixed in [
    ("many-mixed", 100, 1, True),
    ("large-mixed", 4, 32, True),
    ("large-incompressible", 4, 32, False),
]:
    samples = []
    for repetition in range(args.repetitions):
        directory = args.output / "inputs" / corpus / str(repetition)
        directory.mkdir(parents=True)
        for index in range(count):
            artifact = directory / f"Module{index}.xcframework"
            shutil.copytree(sources[index % len(sources)], artifact, symlinks=True)
            libraries = plistlib.loads((artifact / "Info.plist").read_bytes())["AvailableLibraries"]
            assert len(libraries) == 3, "Expected iOS device, iOS simulator, and macOS"
            for library in libraries:
                framework = artifact / library["LibraryIdentifier"] / library["LibraryPath"]
                resources = framework / (
                    "Versions/A/Resources" if library["SupportedPlatform"] == "macos" else "Resources"
                )
                resources.mkdir(parents=True, exist_ok=True)
                seed = f"{run_id}/{corpus}/{repetition}/{index}/{library['LibraryIdentifier']}"
                rng = random.Random(hashlib.sha256(seed.encode()).digest())
                with (resources / "benchmark-payload.bin").open("wb") as stream:
                    for _ in range(mebibytes * 16):
                        stream.write(rng.randbytes(32768))
                        stream.write(bytes(32768) if mixed else rng.randbytes(32768))
                for resource in range(16):
                    (resources / f"benchmark-{resource}.json").write_text(json.dumps({
                        "seed": seed, "resource": resource, "values": list(range(128)),
                    }))
        regular_files = [p for p in directory.rglob("*") if p.is_file() and not p.is_symlink()]
        samples.append({"regularFileBytes": sum(p.stat().st_size for p in regular_files),
                        "regularFileCount": len(regular_files)})
        print(corpus, repetition, samples[-1], flush=True)
    manifest["corpora"][corpus] = {"modules": count, "payloadMiBPerSDK": mebibytes,
                                   "randomFraction": 0.5 if mixed else 1.0, "samples": samples}
(args.output / "provenance.json").write_text(json.dumps(manifest, indent=2))
