"""Publish a generated integration checkout without replacing immutable versions."""

import re
import shutil
import subprocess
import sys
from pathlib import Path


def git(repository, *args):
    return subprocess.check_output(
        ["git", "-C", str(repository), *args], text=True
    ).strip()


def publish(package, repository, version, source_commit):
    match = re.fullmatch(r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", version)
    if not match or not re.fullmatch(r"[0-9a-f]{40}", source_commit):
        raise ValueError("Expected a stable vMAJOR.MINOR.PATCH and full source commit")
    if (package / "SOURCE_COMMIT").read_text().strip() != source_commit:
        raise ValueError("Package does not match the source commit")
    if git(repository, "status", "--porcelain"):
        raise ValueError("Distribution checkout must be clean")

    tags = git(repository, "tag", "--list").splitlines()
    if version not in tags:
        requested = tuple(map(int, match.groups()))
        for tag in tags:
            if re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag):
                if tuple(map(int, tag[1:].split("."))) > requested:
                    raise ValueError("Refusing to publish behind a newer release")

    # The distribution is generated entirely from the package. Removing tracked
    # files also removes obsolete entry points from future releases.
    git(repository, "rm", "-r", "--ignore-unmatch", ".")
    for item in package.iterdir():
        if item.name == ".git" or item.is_symlink():
            raise ValueError("Unexpected package entry")
        destination = repository / item.name
        if item.is_dir():
            shutil.copytree(item, destination, dirs_exist_ok=True)
        else:
            shutil.copyfile(item, destination)
    # Artifact downloads do not preserve executable bits.
    for executable in ("attach.sh", "hooks/pre-command"):
        path = repository / executable
        if path.exists():
            path.chmod(0o755)
    git(repository, "add", "--all")
    tree = git(repository, "write-tree")
    if version in tags:
        if tree != git(repository, "rev-parse", f"{version}^{{tree}}"):
            raise ValueError(f"Immutable release {version} contains different content")
        git(repository, "reset", "--hard", "HEAD")
        print(f"{repository.name}: {version} already published with identical content")
        return

    git(repository, "config", "user.name", "github-actions")
    git(repository, "config", "user.email", "github-actions@github.com")
    git(repository, "commit", "--allow-empty", "-m", f"Release {version}")
    git(repository, "tag", version)
    major = f"v{match[1]}"
    git(repository, "tag", "--force", major)
    git(repository, "push", "--atomic", "origin", "HEAD:main", f"refs/tags/{version}", f"+refs/tags/{major}")
    print(f"{repository.name}: published {version} and {major}")


if __name__ == "__main__":
    publish(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3], sys.argv[4])
