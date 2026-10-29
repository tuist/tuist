#!/usr/bin/env python3
"""Validate a stable SDK patch source; never check out or execute that source."""

import os
import re
import subprocess
import sys


def git(*args):
    return subprocess.check_output(["git", *args], text=True).strip()


def require(condition, message):
    if not condition:
        sys.exit(message)


def main():
    require(
        os.environ.get("GITHUB_REPOSITORY") == "tuist/tuist"
        and os.environ.get("GITHUB_REF") == "refs/heads/main"
        and os.environ.get("GITHUB_EVENT_NAME") == "workflow_dispatch",
        "Stable releases must be dispatched from tuist/tuist main",
    )
    require(len(sys.argv) == 4, "Provide source SHA, base tag and patch version together")
    source, base, version = sys.argv[1:]
    require(re.fullmatch(r"[0-9a-f]{40}", source), "Source must be a full immutable commit SHA")
    semver = r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    match = re.fullmatch(r"tuist-ex@" + semver, base)
    require(match, "Base must be an exact stable tuist-ex@ tag")
    major, minor, patch = map(int, match.groups())
    require(version == f"{major}.{minor}.{patch + 1}", "Only the next patch version is allowed")
    tags = git("tag", "--list", "tuist-ex@*").splitlines()
    stable = [(tuple(map(int, m.groups())), tag) for tag in tags
              if (m := re.fullmatch(r"tuist-ex@" + semver, tag))]
    require(stable and max(stable)[1] == base, "Base must be the latest stable SDK tag")
    require(f"tuist-ex@{version}" not in tags, "Target tag already exists; never replace a release")
    branch = f"refs/remotes/origin/releases/tuist-ex-{major}.{minor}.x"
    require(git("rev-parse", f"{branch}^{{commit}}") == source,
            "Source must be the current stable release branch tip, not a PR or main SHA")
    base_sha = git("rev-parse", f"refs/tags/{base}^{{commit}}")
    require(source != base_sha, "Source must contain a patch after the stable tag")
    subprocess.run(["git", "merge-base", "--is-ancestor", base_sha, source], check=True)
    changed = git("diff", "--name-only", "-z", base_sha, source).removesuffix("\0").split("\0")
    require(any(path.startswith("tuist_ex/") for path in changed), "No SDK changes to publish")
    require(all(path.startswith("tuist_ex/") or path == ".github/workflows/tuist-ex.yml"
                for path in changed), "Stable source includes changes outside the SDK and its validation")
    outputs = {
        "tuist-ex-should-release": "true",
        "tuist-ex-next-version": f"tuist-ex@{version}",
        "tuist-ex-next-version-number": version,
        "source-sha": source,
        "base-tag": base,
    }
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        for key, value in outputs.items():
            print(f"{key}={value}", file=output)
    print(f"Validated {base} ({base_sha}) -> tuist-ex@{version} from {source}")


if __name__ == "__main__":
    main()
