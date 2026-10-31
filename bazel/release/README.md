# rules_tuist releases (operator guide)

## Distribution

Recommend the commit-pinned `git_override` setup in [the module guide](../README.md).
Consumers fetch `bazel/` directly from the public Tuist repository, without
registry authentication or a separate installation step. Bazel first attempts
a shallow fetch of the selected commit and falls back to a full fetch if needed.
Pin the source commit associated with the desired canary, RC or stable release.
Source archives with checksums provide an alternative to Git dependencies.

Native Android/iOS build and preview publication acceptance are separate work;
the release gate runs portable Python tests and the public companion launcher
driver, `python3 tests/runtime/runtime_test.py`, on Bazel 9.3.1. The host-Python
driver invokes actual `bazel run` commands for all public preview targets with
directory and manifest-only runfiles, including `--help` and disabled-publication
variants. Child processes receive failing host Python/Tuist shims. The fixtures
use minimal application providers; the executable fixture builds a real C++
binary and shared library. It verifies loopback publication, replay and execution
of the extracted distribution, not a live Tuist upload. A native C++ toolchain
is required. The driver does not depend on a `py_test` or publisher `py_binary` bootstrap.

## Consume a source release archive

Choose an actually published version from the repository's GitHub releases and
download its `.tar.gz.sha256` asset. For a `0.1.0-rc.1` release:

```starlark
bazel_dep(name = "rules_tuist", version = "0.1.0-rc.1")
archive_override(
    module_name = "rules_tuist",
    urls = ["https://github.com/tuist/tuist/releases/download/rules_tuist@0.1.0-rc.1/rules_tuist-0.1.0-rc.1.tar.gz"],
    strip_prefix = "rules_tuist-0.1.0-rc.1",
    sha256 = "<64-character digest from the matching checksum asset>",
)
```

Replace the version in every field and pin the checksum; do not use a mutable
main archive. Keep the override to resolve directly from the release asset.
The same format works for stable and canary source archives.

## Release train and first-release bootstrap

`.github/workflows/bazel-release.yml` uses the CLI/Kura train's tag-based minor
selection with one difference: an empty tag set starts at `0.1.0`, with no
synthetic anchor tag needed. Only `rules_tuist@` tags participate.

* Relevant pushes to `main` publish `rules_tuist@X.Y.0-canary.N`. The source SHA
  is the triggering push's commit, even if main moves while queued. A previously
  tagged canary SHA is skipped. Canary tags do not themselves advance the minor.
* Mondays at **06:00 UTC**, the single serialized workflow first promotes the
  newest pending RC line, then cuts the next minor's `rc.1` from main. On the
  first Monday there is nothing to promote, so it only cuts `0.1.0-rc.1`.
  Both archives must pass validation before either is published. If promotion
  is rejected, no new line is cut.
* An initial RC creates `releases/rules-tuist-X.Y.x` at the exact source SHA,
  atomically with its tag. The existence of that RC tag advances main's next
  canary minor: after `0.1.0-rc.1`, canaries target `0.2.0`.
* Fix an RC line through reviewed cherry-picks to its release branch, then
  dispatch **rules_tuist Release**, selecting workflow ref **main**, channel
  `rc`, and branch `releases/rules-tuist-X.Y.x`. This publishes `rc.(N+1)` from
  that branch's tip, not main. With no existing RC, iteration is rejected.
* Dispatch channel `rc-new` with an empty branch to start a line early. Dispatch
  channel `promote` with its release branch to promote early (an empty branch
  chooses the newest pending line). Allow the RC to soak before doing so.
* Promotion requires the live release-branch tip to equal the **latest RC's
  source commit**. An unpublished fix blocks promotion until another RC has
  been cut and soaked. Promotion reuses that exact commit, never newer main.
  Stable lines are closed to RC iteration; patch/backport automation is not
  implemented here.

Canaries and RCs use GitHub `--prerelease --latest=false`; stable releases use
`--latest=true` without `--prerelease`. The workflow itself enforces ordering;
it does not rely on tag pushes or release events to trigger a second workflow.
It shares one concurrency group across all operations. GitHub may replace a
pending run when newer pushes arrive; the gate preserves the exact SHA for
each run that executes, not a guarantee that Actions retains every queued run.

## Archive contract and trust boundary

Every release has two assets:

* `rules_tuist-<version>.tar.gz`, rooted at `rules_tuist-<version>/`;
* `rules_tuist-<version>.tar.gz.sha256`, usable with `sha256sum -c`.

The archive reads tracked `bazel/` files and the repository-root `LICENSE.md`
from the selected commit using `git archive`. It excludes `bazel/release/`
control code and rejects tracked build junk and symlinks.
The module is flattened to the archive root, with its `MODULE.bazel` version
stamped to the release version. Other module dependencies remain unchanged.
Untracked files, dirty checkout edits and build outputs never enter the asset.
Tracked `tests/runtime` sources ship with the module so the release gate tests
the extracted asset. Its generated `MODULE.bazel.lock` is excluded unless
intentionally tracked in the selected source commit, like other lockfiles.
The Git tag points to the original, unstamped source commit; only the asset's
module version is stamped. Do not use GitHub's automatically generated monorepo
source tarball as the module asset. Archive timestamps/ownership and gzip time
are normalized; publishing rebuilds the archive from the selected SHA and
requires byte-for-byte equality with the validated artifact and its checksum.

Planning/control code is checked out from main and pinned for the entire run.
Dispatches from any other workflow ref are skipped. Branch names are validated
against the release namespace **before** they are resolved. Candidate code is
only executed in a separate read-only validation job with no persisted checkout
credentials or release token. The write-enabled publisher executes only pinned
main control code, re-fetches refs/tags, rechecks the version and branch tip,
and publishes the validated archive. Changes to main while a run is executing
do not change that run's selected source or control code.

Before enabling releases, operators must:

1. Merge the module rename, hermetic Python launcher, these workflows and their
   tests together; source commits predating `rules_tuist` will fail packaging.
2. Enable Actions and allow its `GITHUB_TOKEN` contents-write permission in the
   publication job. No release PAT is needed: downstream tag/release-event
   workflows are intentionally not used.
3. Protect `main`, `releases/rules-tuist-*` and `rules_tuist@*` with reviewed
   branch updates and immutable published tags. Permit the workflow identity
   to create release branches and tags under those rules. Freeze edits to a
   release branch during publication: GitHub cannot atomically compare a branch
   tip and create an unrelated tag, so protections/process close the final
   check-to-push race. Restrict manual tag writes to avoid races with the train.
4. Confirm the repository's GitHub release "Latest" policy: stable publication
   explicitly sets Latest in this monorepo, just as the CLI/Kura trains do.
5. Observe the first canary, dispatch `rc-new` (or wait until Monday), inspect
   the archive/checksum, then allow an RC to soak before stable promotion.

### Partial publication recovery

Git refs and GitHub releases cannot be committed in one transaction. If the tag
push succeeds but `gh release create` fails, stop and inspect the remote tag,
GitHub release and run artifacts before proceeding. Never delete/repoint a
published tag or substitute newer main contents. Regenerate the versioned asset
from the **original tag's source SHA**, verify its checksum against the tested
run artifact, and finish that release manually with its correct prerelease and
Latest flags. If the release already exists, inspect its assets before adding
missing ones; do not blindly replace them. The automatic resolver deliberately
does not overwrite an existing version or retry an ambiguous GitHub write.
After finishing a failed weekly promotion, dispatch `rc-new` if its subsequent
cut did not happen; rerunning `promote` for an already-stable line is rejected.

## Local checks and packaging

From the repository root:

```sh
python3 .github/scripts/bazel-release.test.py
python3 -m unittest discover -s bazel/tests -p 'test_*.py'
(cd bazel && USE_BAZEL_VERSION=9.3.1 python3 tests/runtime/runtime_test.py)
actionlint .github/workflows/bazel-release.yml .github/workflows/bazel-tests.yml
# A clean, committed source SHA whose module name is already rules_tuist:
python3 bazel/release/release.py package <source-sha> 0.1.0-rc.1 /tmp/rules-tuist-assets
(cd /tmp/rules-tuist-assets && sha256sum -c rules_tuist-0.1.0-rc.1.tar.gz.sha256)
```

For local testing of current uncommitted changes, copy the intended module files
and root license into a **disposable repository**, commit them there and package
that disposable SHA. The packager never offers a dirty-working-tree release
mode. The regression suite uses disposable Git repositories and local bare
remotes; it stubs only `gh`, so running it cannot publish external releases.
