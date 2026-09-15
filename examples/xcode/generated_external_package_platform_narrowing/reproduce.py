#!/usr/bin/env python3
"""Exercise real package loading, cache warming, replacement, and Xcode linking."""

import argparse
import atexit
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import socket
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tuist", required=True, help="Path to the Tuist executable to test")
    parser.add_argument(
        "--expect-reuse", action="store_true",
        help="Fail until narrower graphs reuse the combined warm",
    )
    args = parser.parse_args()
    executable = str(Path(args.tuist).resolve())
    output = Path(tempfile.mkdtemp(prefix="tuist-platform-narrowing-")).resolve()
    print(f"Evidence directory: {output}", flush=True)
    fixture = output / "fixture"
    shutil.copytree(
        Path(__file__).parent, fixture,
        ignore=shutil.ignore_patterns(
            ".build", "*.xcodeproj", "*.xcworkspace", "Derived", "Package.resolved", "__pycache__",
        ),
    )
    environment = {key: value for key, value in os.environ.items() if not key.startswith("TUIST_")}
    environment.update(
        TUIST_XDG_CACHE_HOME=str(output / "cache"),
        TUIST_XDG_STATE_HOME=str(output / "state"),
        TUIST_XDG_CONFIG_HOME=str(output / "config"),
        TUIST_CONSUMER_SCOPE="combined",
    )

    def run(label, command, cwd=fixture):
        print(label, flush=True)
        with (output / f"{label}.log").open("w") as log:
            result = subprocess.run(
                command, cwd=cwd, env=environment, stdout=log, stderr=subprocess.STDOUT,
            )
        text = (output / f"{label}.log").read_text()
        if result.returncode:
            raise RuntimeError(f"{label} failed: {text[-6000:]}")
        return text

    def tuist(label, *arguments):
        return run(label, [executable, *arguments])

    def generate(label, scope, root):
        environment["TUIST_CONSUMER_SCOPE"] = scope
        text = tuist(label, "generate", "--no-open", "--configuration", "Debug", root)
        project = (fixture / "PlatformNarrowing.xcodeproj/project.pbxproj").read_text()
        hits = {name for name in ("Leaf", "Shared") if f"{name}.xcframework" in project}
        reported_hits = text.split("Using cache binaries for the following targets:")[-1].splitlines()[0]
        assert ("Shared" in hits) == ("Shared" in reported_hits)
        return hits

    def artifacts(cache):
        result = {}
        for name in ("Leaf", "Shared"):
            paths = list(cache.glob(f"tuist/Binaries/*/{name}.xcframework"))
            assert len(paths) == 1, (name, paths)
            result[name] = paths[0]
        return result

    def slices(path):
        with (path / "Info.plist").open("rb") as file:
            libraries = plistlib.load(file)["AvailableLibraries"]
        return {(item["SupportedPlatform"], item.get("SupportedPlatformVariant", "")) for item in libraries}

    run("version", [executable, "version"])
    run("xcode-version", ["xcodebuild", "-version"])
    package = fixture / "LocalPackage"
    run("git-init", ["git", "init", "--initial-branch=main"], cwd=package)
    run("git-add", ["git", "add", "Package.swift", "Sources"], cwd=package)
    run("git-commit", [
        "git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
        "-c", "commit.gpgsign=false", "commit", "-m", "Synthetic package",
    ], cwd=package)
    run("git-tag", ["git", "-c", "tag.gpgSign=false", "tag", "1.0.0"], cwd=package)
    # A file URL is classified as localSourceControl and bypasses revision-based hashing.
    # Serve only this synthetic package over loopback to exercise remoteSourceControl.
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
    # SwiftPM identities ignore URL ports. Give every run a distinct repository
    # name so its shared security fingerprints cannot collide with earlier runs.
    remote_name = "package-" + output.name.removeprefix("tuist-platform-narrowing-")
    remote_package = fixture / remote_name
    package.rename(remote_package)
    daemon = subprocess.Popen([
        "git", "daemon", "--reuseaddr", "--export-all", "--listen=127.0.0.1",
        f"--port={port}", f"--base-path={fixture}", str(remote_package),
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def stop_daemon():
        daemon.terminate()
        daemon.wait()

    atexit.register(stop_daemon)
    manifest = fixture / "Tuist/Package.swift"
    manifest.write_text(manifest.read_text().replace(
        "../LocalPackage", f"git://127.0.0.1:{port}/{remote_name}",
    ))
    tuist("install", "install")
    tuist(
        "warm-combined", "cache", "PhoneConsumer", "MacConsumer",
        "--no-upload", "--cache-profile", "only-external", "--configuration", "Debug",
    )
    combined_artifacts = artifacts(output / "cache")
    expected_slices = {("ios", ""), ("ios", "simulator"), ("macos", "")}
    assert all(slices(path) == expected_slices for path in combined_artifacts.values())
    hits = {}
    for scope, root in [
        ("combined", "PhoneConsumer"), ("combined", "MacConsumer"),
        ("ios", "PhoneConsumer"), ("macos", "MacConsumer"),
    ]:
        label = f"generate-{scope}-{root}"
        hits[label] = sorted(generate(label, scope, root))
        if scope == "combined":
            assert set(hits[label]) == {"Leaf", "Shared"}, "Focusing the same loaded graph must reuse the warm"

    settings = {}
    compilation_keys = [
        "SWIFT_VERSION", "SWIFT_ACTIVE_COMPILATION_CONDITIONS", "OTHER_SWIFT_FLAGS",
        "SWIFT_OPTIMIZATION_LEVEL", "ENABLE_TESTABILITY", "GCC_PREPROCESSOR_DEFINITIONS",
        "CLANG_ENABLE_MODULES", "DEFINES_MODULE", "MACH_O_TYPE", "ARCHS",
        "IPHONEOS_DEPLOYMENT_TARGET", "MACOSX_DEPLOYMENT_TARGET", "SUPPORTS_MACCATALYST",
    ]
    for scope in ("combined", "ios", "macos"):
        environment["TUIST_CONSUMER_SCOPE"] = scope
        tuist(f"source-{scope}", "generate", "--no-open", "--cache-profile", "none")
        project = fixture / "Tuist/.build/tuist-derived/Projects/LocalPackage/LocalPackage.xcodeproj"
        sdks = {
            "combined": ["iphoneos", "iphonesimulator", "macosx"],
            "ios": ["iphoneos", "iphonesimulator"],
            "macos": ["macosx"],
        }[scope]
        for sdk in sdks:
            data = json.loads(run(f"settings-{scope}-{sdk}", [
                "xcodebuild", "-showBuildSettings", "-json", "-project", str(project),
                "-target", "Shared", "-configuration", "Debug", "-sdk", sdk,
            ]))
            effective = next(item["buildSettings"] for item in data if item["target"] == "Shared")
            # Unrelated deployment targets are pruned. Catalyst eligibility does
            # not affect native macOS compilation (NO versus an omitted setting).
            irrelevant = (
                {"IPHONEOS_DEPLOYMENT_TARGET", "SUPPORTS_MACCATALYST"}
                if sdk == "macosx" else {"MACOSX_DEPLOYMENT_TARGET"}
            )
            relevant = [key for key in compilation_keys if key not in irrelevant]
            settings[f"{scope}-{sdk}"] = {key: effective.get(key) for key in relevant}
            if scope != "combined":
                assert settings[f"{scope}-{sdk}"] == settings[f"combined-{sdk}"], "Effective compilation settings changed"

    # Explicit dependencies validate compatibility without changing or aliasing cache keys.
    artifact_directory = output / "combined-artifacts"
    artifact_directory.mkdir()
    for name, path in combined_artifacts.items():
        shutil.copytree(path, artifact_directory / f"{name}.xcframework")
    environment["TUIST_ARTIFACT_DIRECTORY"] = str(artifact_directory)
    for scope, root, destinations in [
        ("ios", "PhoneConsumer", ["generic/platform=iOS Simulator", "generic/platform=iOS"]),
        ("macos", "MacConsumer", ["platform=macOS,arch=arm64"]),
    ]:
        environment["TUIST_CONSUMER_SCOPE"] = scope
        tuist(f"explicit-{scope}", "generate", "--no-open", "--cache-profile", "none")
        for index, destination in enumerate(destinations):
            run(f"build-explicit-{scope}-{index}", [
                "xcodebuild", "build", "-workspace", "PlatformNarrowing.xcworkspace", "-scheme", root,
                "-configuration", "Debug", "-destination", destination,
                "-derivedDataPath", str(output / f"build-{scope}-{index}"),
                "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=",
            ])
    assert run("run-macos", [str(output / "build-macos-0/Build/Products/Debug/MacConsumer")]).strip() == "macOS"
    del environment["TUIST_ARTIFACT_DIRECTORY"]

    # The reverse direction must remain a miss: an iOS-only artifact has no macOS slice.
    environment["TUIST_XDG_CACHE_HOME"] = str(output / "ios-cache")
    environment["TUIST_CONSUMER_SCOPE"] = "ios"
    tuist(
        "warm-ios", "cache", "PhoneConsumer",
        "--no-upload", "--cache-profile", "only-external", "--configuration", "Debug",
    )
    ios_artifacts = artifacts(output / "ios-cache")
    assert all(slices(path) == expected_slices - {("macos", "")} for path in ios_artifacts.values())
    assert generate("generate-combined-after-ios-warm", "combined", "MacConsumer") == set()
    assert generate("generate-ios-after-ios-warm", "ios", "PhoneConsumer") == {"Leaf", "Shared"}

    # Require the actual remote-package hasher branch, even though the Git transport is local.
    logs = "\n".join(path.read_text() for path in (output / "state").glob("tuist/sessions/*/logs.txt"))
    hashes = {}
    hash_inputs = {"Leaf": {}, "Shared": {}}
    for name, digest, components in re.findall(
        r"Target content hash for (Leaf|Shared) \(external project\): ([a-f0-9]+)\n\s*Components:\n((?:[ \t]+[^\n]*\n)+)", logs
    ):
        hash_inputs[name][digest] = dict(re.findall(r"^\s*(\w+): (.*)$", components, re.MULTILINE))
    for name in ("Leaf", "Shared"):
        hashes[name] = sorted(set(re.findall(rf"Target content hash for {name} \(external project\): ([a-f0-9]+)", logs)))
        assert len(hashes[name]) >= 3, f"Expected external-package hashes for three destination sets: {name}"
        assert set(hash_inputs[name]) == set(hashes[name])
        for key in ("project", "name", "product", "projectSettings", "targetSettings", "embeddedProductReferences", "additionalStrings"):
            assert len({fields[key] for fields in hash_inputs[name].values()}) == 1, (name, key)
    leaf_by_destinations = {fields["destinations"]: digest for digest, fields in hash_inputs["Leaf"].items()}
    for fields in hash_inputs["Leaf"].values():
        assert fields["dependencies"] == hashlib.md5(b"").hexdigest()
    for fields in hash_inputs["Shared"].values():
        assert fields["dependencies"] == hashlib.md5(leaf_by_destinations[fields["destinations"]].encode()).hexdigest()
    summary = {
        "generation_hits": hits,
        "external_hashes": hashes,
        "hash_inputs": hash_inputs,
        "compilation_settings": settings,
        "combined_slices": sorted(expected_slices),
        "explicit_builds": "iOS device, iOS simulator, macOS; macOS executable ran",
        "reverse_reuse_rejected": True,
    }
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2), flush=True)
    narrower_hits = [value for label, value in hits.items() if "-combined-" not in label]
    if args.expect_reuse:
        assert all(set(value) == {"Leaf", "Shared"} for value in narrower_hits), "Known limitation: narrower graphs miss compatible combined artifacts"
    else:
        assert all(value == [] for value in narrower_hits), "Behavior changed: rerun with --expect-reuse and review compatibility"
    print(f"All checks passed. Evidence: {output}", flush=True)


if __name__ == "__main__":
    main()
