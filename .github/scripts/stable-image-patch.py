#!/usr/bin/env python3
"""Validate a server or Kura patch without checking out or executing its source."""

import os
import re
import subprocess
import sys


def git(*args):
    return subprocess.check_output(["git", *args], text=True).rstrip("\n")


def require(condition, message):
    if not condition:
        sys.exit(message)


def main():
    require(
        os.environ.get("GITHUB_REPOSITORY") == "tuist/tuist"
        and os.environ.get("GITHUB_REF") == "refs/heads/main"
        and os.environ.get("GITHUB_EVENT_NAME") == "workflow_dispatch",
        "Stable patches must be dispatched from tuist/tuist main",
    )
    require(len(sys.argv) == 4, "Provide component, source SHA and stable base tag")
    component, source, base = sys.argv[1:]
    require(
        component in ("server", "kura"),
        "Only server and Kura image patches are supported",
    )
    require(
        re.fullmatch(r"[0-9a-f]{40}", source),
        "Source must be a full immutable commit SHA",
    )
    semver = r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    match = re.fullmatch(component + "@" + semver, base)
    require(match, "Base must be an exact stable tag for the selected component")
    major, minor, patch = map(int, match.groups())
    version = f"{major}.{minor}.{patch + 1}"
    if "EXPECTED_VERSION" in os.environ:
        require(
            os.environ["EXPECTED_VERSION"] == version, "Planned patch version changed"
        )

    # Read remote tags, not a checkout's possibly stale tag cache. Fetch the
    # exact base and branch again on every invocation, including publication.
    remote_tags = git(
        "ls-remote", "--tags", "--refs", "origin", f"refs/tags/{component}@*"
    )
    tags = [
        line.split("\t")[1].removeprefix("refs/tags/")
        for line in remote_tags.splitlines()
    ]
    stable = [
        (tuple(map(int, m.groups())), tag)
        for tag in tags
        if (m := re.fullmatch(component + "@" + semver, tag))
        and tuple(map(int, m.groups()[:2])) == (major, minor)
    ]
    require(
        stable and max(stable)[1] == base,
        "Base must be the latest published stable tag on the selected release line",
    )
    require(
        f"{component}@{version}" not in tags,
        "Target tag already exists; never replace a release",
    )
    branch = f"releases/{component}-{major}.{minor}.x"
    remote = f"refs/remotes/origin/{branch}"
    git(
        "fetch",
        "--force",
        "--no-tags",
        "origin",
        f"+refs/tags/{base}:refs/tags/{base}",
        f"+refs/heads/{branch}:{remote}",
    )
    require(
        git("rev-parse", f"{remote}^{{commit}}") == source,
        "Source must equal the current merged stable branch tip",
    )
    base_sha = git("rev-parse", f"refs/tags/{base}^{{commit}}")
    if "APPROVED_BASE_SHA" in os.environ:
        require(
            os.environ["APPROVED_BASE_SHA"] == base_sha,
            "Stable base changed since planning",
        )
    require(source != base_sha, "Source must contain a patch after the stable tag")
    require(
        subprocess.run(
            ["git", "merge-base", "--is-ancestor", base_sha, source], check=False
        ).returncode
        == 0,
        "Stable tag must be an ancestor of the selected source",
    )
    changed = (
        git("diff", "--no-renames", "--name-only", "-z", base_sha, source)
        .removesuffix("\0")
        .split("\0")
    )
    allowed = (f"{component}/",)
    if component == "server":
        allowed += ("tuist_common/",)
    files = (
        "infra/certificate-trust/policy.json",
        "infra/certificate-trust/pem-store.sh",
        f".github/workflows/{component}.yml",
    )
    require(
        any(path.startswith(f"{component}/") for path in changed),
        "No component changes to publish",
    )
    require(
        all(path.startswith(allowed) or path in files for path in changed),
        "Stable patch includes changes outside its component, trust policy and validation",
    )
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        for key, value in {
            "version": version,
            "sha": source,
            "base_tag": base,
            "base_sha": base_sha,
            "branch": branch,
        }.items():
            print(f"{key}={value}", file=output)
    print(f"Validated {base} ({base_sha}) -> {component}@{version} from {source}")


if __name__ == "__main__":
    main()
