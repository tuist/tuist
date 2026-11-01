#!/usr/bin/env python3
"""Trusted-main control plane for rules_tuist source releases."""

import argparse
import gzip
import hashlib
import io
import json
import re
import subprocess
import tarfile
import tempfile
from pathlib import Path

PREFIX = "rules_tuist@"
VERSION = re.compile(
    r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-(canary|rc)\.([1-9]\d*))?"
)
BRANCH = re.compile(r"releases/rules-tuist-(0|[1-9]\d*)\.(0|[1-9]\d*)\.x")


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def git(*args):
    return run("git", *args)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def commit(ref):
    return git("rev-parse", "--verify", f"{ref}^{{commit}}")


def remote_branch(branch):
    refs = git("ls-remote", "--heads", "origin", f"refs/heads/{branch}")
    return refs.split()[0] if refs else None


def tags():
    result = {}
    for tag in git("tag", "--list", f"{PREFIX}*").splitlines():
        match = VERSION.fullmatch(tag.removeprefix(PREFIX))
        if match:
            major, minor, patch, channel, number = match.groups()
            result[tag.removeprefix(PREFIX)] = (
                int(major),
                int(minor),
                int(patch),
                channel,
                int(number or 0),
            )
    return result


def ancestor(older, newer):
    require(
        subprocess.run(
            ["git", "merge-base", "--is-ancestor", older, newer], check=False
        ).returncode
        == 0,
        "Source must descend from the expected trusted history",
    )


def plan(channel, branch="", sha=""):
    # Validate the namespace before interpreting any operator-supplied ref.
    require(
        not branch or BRANCH.fullmatch(branch),
        "Invalid rules_tuist release branch namespace",
    )
    require(channel in {"canary", "rc-new", "rc", "promote"}, "Unknown release channel")
    require(
        not branch or channel in {"rc", "promote"}, "Branch only applies to rc/promote"
    )
    versions = tags()
    anchors = [v[:2] for v in versions.values() if v[3] in {None, "rc"}]
    major, minor = max(anchors) if anchors else (0, 0)
    target = f"{major}.{minor + 1}.0"
    create_branch = channel == "rc-new"
    if channel in {"canary", "rc-new"}:
        sha = commit(sha or "refs/remotes/origin/main")
        ancestor(sha, commit("refs/remotes/origin/main"))
        if channel == "canary":
            # Re-running a successful push should not mint a duplicate version.
            if any(
                v[3] == "canary" and commit(PREFIX + t) == sha
                for t, v in versions.items()
            ):
                return None
        else:
            branch = f"releases/rules-tuist-{major}.{minor + 1}.x"
            require(
                remote_branch(branch) is None,
                "Release branch already exists; iterate with rc",
            )
    else:
        if not branch and channel == "promote":
            stable_lines = [v[:2] for v in versions.values() if v[3] is None]
            stable_line = max(stable_lines, default=(-1, -1))
            pending = [
                v[:2] for v in versions.values() if v[3] == "rc" and v[:2] > stable_line
            ]
            if not pending:
                return None
            major, minor = max(pending)
            branch = f"releases/rules-tuist-{major}.{minor}.x"
        require(branch, "An existing release branch is required")
        match = BRANCH.fullmatch(branch)
        target = f"{match[1]}.{match[2]}.0"
        require(target not in versions, "Release line is already stable")
        tip = remote_branch(branch)
        require(tip, "Release branch does not exist")
        sha = commit(tip)
        candidates = [
            v[4] for t, v in versions.items() if t.startswith(target + "-rc.")
        ]
        require(candidates, "Publish an initial RC before iterating or promoting")
        latest_rc = commit(f"{PREFIX}{target}-rc.{max(candidates)}")
        if channel == "promote":
            require(
                sha == latest_rc,
                "Release branch moved beyond latest RC; publish and soak another RC",
            )
        else:
            ancestor(latest_rc, sha)
    if channel == "promote":
        version = target
    else:
        suffix = "canary" if channel == "canary" else "rc"
        numbers = [
            v[4] for t, v in versions.items() if t.startswith(f"{target}-{suffix}.")
        ]
        version = f"{target}-{suffix}.{max(numbers, default=0) + 1}"
    return {
        "channel": channel,
        "version": version,
        "sha": sha,
        "branch": branch,
        "create_branch": create_branch,
        "prerelease": channel != "promote",
        "latest": channel == "promote",
    }


def package(sha, version, output):
    require(VERSION.fullmatch(version), "Invalid release version")
    sha = commit(sha)
    # git archive reads only the selected commit, never the dirty checkout or
    # untracked build outputs. Read members without extracting candidate paths.
    source = subprocess.check_output(
        ["git", "archive", "--format=tar", sha, "bazel", "LICENSE.md"]
    )
    files = {}
    with tarfile.open(fileobj=io.BytesIO(source)) as archive:
        for entry in archive:
            if not entry.isfile():
                require(
                    entry.isdir(),
                    "Source archive must not contain symlinks or special files",
                )
                continue
            name = entry.name
            if name.startswith("bazel/"):
                name = name.removeprefix("bazel/")
                if name.startswith("release/"):
                    continue
            elif name != "LICENSE.md":
                continue
            require(
                not any(
                    p in {"..", "__pycache__", ".git"} or p.startswith("bazel-")
                    for p in Path(name).parts
                )
                and not name.endswith(".pyc"),
                "Tracked build junk in module source",
            )
            files[name] = (archive.extractfile(entry).read(), entry.mode)
    require(
        "MODULE.bazel" in files and "LICENSE.md" in files,
        "Module and root license are required",
    )
    module = files["MODULE.bazel"][0].decode()
    module_call = re.search(r"\bmodule\s*\((.*?)\)", module, re.DOTALL)
    require(module_call is not None, "Missing module declaration")
    require(
        re.search(r'\bname\s*=\s*[\'"]rules_tuist[\'"]', module_call[1]),
        "Unexpected module name",
    )
    stamped, count = re.subn(
        r'(\bversion\s*=\s*)[\'"][^\'"]*[\'"]',
        lambda m: m[1] + json.dumps(version),
        module_call[1],
    )
    require(count == 1, "Expected exactly one module version")
    module = module[: module_call.start(1)] + stamped + module[module_call.end(1) :]
    files["MODULE.bazel"] = (module.encode(), files["MODULE.bazel"][1])
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    asset = output / f"rules_tuist-{version}.tar.gz"
    with (
        asset.open("wb") as raw,
        gzip.GzipFile(fileobj=raw, mode="wb", filename="", mtime=0) as compressed,
        tarfile.open(
            fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT
        ) as archive,
    ):
        for name, (data, mode) in sorted(files.items()):
            entry = tarfile.TarInfo(f"rules_tuist-{version}/{name}")
            entry.size, entry.mode, entry.mtime = len(data), mode, 0
            archive.addfile(entry, io.BytesIO(data))
    digest = hashlib.sha256(asset.read_bytes()).hexdigest()
    asset.with_suffix(asset.suffix + ".sha256").write_text(f"{digest}  {asset.name}\n")
    return asset


def publish(item, output):
    # Re-resolve using fresh remote refs/tags, but retain the selected main SHA.
    git("fetch", "origin", "+refs/heads/*:refs/remotes/origin/*", "--tags")
    expected = plan(
        item["channel"],
        item["branch"] if not item["create_branch"] else "",
        item["sha"],
    )
    require(
        expected == item, "Release state changed since validation; start a fresh run"
    )
    asset = Path(output) / f"rules_tuist-{item['version']}.tar.gz"
    # Rebuild from the same immutable source with trusted code and compare to
    # the tested payload, rather than trusting downloaded asset contents.
    with tempfile.TemporaryDirectory() as temp:
        rebuilt = package(item["sha"], item["version"], temp)
        require(
            asset.read_bytes() == rebuilt.read_bytes(),
            "Validated archive does not match exact source",
        )
        checksum = asset.with_suffix(asset.suffix + ".sha256")
        require(
            checksum.read_bytes()
            == rebuilt.with_suffix(rebuilt.suffix + ".sha256").read_bytes(),
            "Checksum mismatch",
        )
    tag = PREFIX + item["version"]
    refs = [f"{item['sha']}:refs/tags/{tag}"]
    if item["create_branch"]:
        refs.append(f"{item['sha']}:refs/heads/{item['branch']}")
    git("push", "--atomic", "origin", *refs)
    args = [
        "gh",
        "release",
        "create",
        tag,
        str(asset),
        str(checksum),
        "--verify-tag",
        "--title",
        tag,
        "--notes",
        f"rules_tuist source release from {item['sha']}.",
        f"--latest={str(item['latest']).lower()}",
    ]
    if item["prerelease"]:
        args.append("--prerelease")
    subprocess.run(args, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    resolve = commands.add_parser("plan")
    resolve.add_argument(
        "channel", choices=["canary", "rc-new", "rc", "promote", "weekly"]
    )
    resolve.add_argument("--branch", default="")
    resolve.add_argument("--sha", default="")
    archive = commands.add_parser("package")
    archive.add_argument("sha")
    archive.add_argument("version")
    archive.add_argument("output")
    release = commands.add_parser("publish")
    release.add_argument("plans", help="JSON array emitted by plan")
    release.add_argument("output")
    args = parser.parse_args()
    if args.command == "plan":
        require(
            not args.branch or BRANCH.fullmatch(args.branch),
            "Invalid rules_tuist release branch namespace",
        )
        git("fetch", "origin", "+refs/heads/*:refs/remotes/origin/*", "--tags")
        if args.channel == "weekly":
            require(
                not args.branch and not args.sha,
                "Weekly uses trusted main and the pending RC",
            )
            plans = [plan("promote"), plan("rc-new")]
        else:
            plans = [plan(args.channel, args.branch, args.sha)]
        print(json.dumps([item for item in plans if item], separators=(",", ":")))
    elif args.command == "package":
        print(package(args.sha, args.version, args.output))
    else:
        for item in json.loads(args.plans):
            publish(item, args.output)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error)) from error
