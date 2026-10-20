# Tuist Cache Volume

Attach a private writable clone of the latest committed snapshot. Each key is
scoped to your account, repository, CPU architecture, and execution user. Jobs
on different hosts can reuse the same cache. Concurrent jobs have isolated
clones. No `id-token` permission or workflow credential is required.

Attach after checkout and before your tools populate the directories. List
every directory to keep, one per line:

```yaml
- uses: tuist/cache-volume@v1
  with:
    path: |
      ~/.gradle/caches
      ~/.gradle/wrapper
- run: ./gradlew test
```

Without a `key`, the action attaches the default volume of the job's runner
profile and repository. Name a volume with `key` and set its capacity with
`size`:

```yaml
- uses: tuist/cache-volume@v1
  with:
    key: spm
    size: 50gb
    path: |
      .build
      ~/Library/Caches/org.swift.swiftpm
```

Keep existing runner labels and container images. Native and container jobs use
identical action inputs. Do not restore archive caches into these paths. If you
set `GRADLE_USER_HOME`, use paths beneath that location. Paths must be absent or
empty; the action never deletes existing content. Do not attach the same key
twice in one job. Keep keys stable when
dependencies or tools change: each job starts from the latest saved contents and
your tools update them, so a key that changes with a lockfile hash starts empty
every time.

PRs consume warm snapshots and write
to their own clones; by default only successful default-branch push, manual, and scheduled
jobs publish. Failed jobs and disallowed writers are discarded. Publications
use last-publication-wins. Cache data is disposable and must not contain secrets.

Under **Runners → Volumes**, inspect cache hits, attachment times, retained size,
last use, and job history; clear a volume. Clearing
invalidates old clones immediately for publication and clears the saved head.
Running jobs finish with their private copies. Physical reclamation follows
teardown; unavailable agents remain pending. A future use of the key starts fresh.

## Inputs and output

| Name | Contract |
| --- | --- |
| `key` | Optional stable name within the repository, architecture and execution user, such as `spm-checkouts`. Omit it to use the default volume of the runner profile and repository. Not a content hash: do not include lockfile, tool-version or commit hashes. Use a new key only to start a separate, empty cache. Keys starting with `tuist-` are reserved. |
| `path` | Required. Up to 16 absent or empty directories, one per line. Blank lines and surrounding whitespace are ignored. Absolute paths, workspace-relative paths and `~/` are supported. |
| `size` | Optional volume capacity, a whole number of GB from `1gb` to `100gb`, such as `50gb`. New volumes start at `20gb` without it. |
| `cache-hit` | Output string `true` for a mounted saved snapshot; `false` for a cold directory or unavailable storage. |

Use `id: dependencies` to access `${{ steps.dependencies.outputs.cache-hit }}`.
Continue running the dependency manager on hits: the volume may not contain every
dependency required by the current commit. The action attaches the volume;
the service saves eligible successful jobs after teardown. No post action or
additional workflow permissions are required.

A missing client fails with a Tuist Linux or macOS runner requirement. Unavailable
storage warns and falls back to a job-local directory. Invalid or nonempty paths
and invalid sizes fail without replacing their contents. When saved contents
reach 80% of capacity and a job runs out of space on them, the next job starts
empty.
Linux and macOS fleets must have cache volumes enabled.

### Several directories in one volume

One key holds every directory you list:

```yaml
- uses: tuist/cache-volume@v1
  with:
    key: python-tools
    path: |
      ~/.cache/pip
      ~/.cache/pre-commit
```

- All paths share the volume's capacity and are restored and saved together.
- Paths in one volume must not contain each other.
- A single path keeps the volume's contents when it changes. With several
  paths, each has its own directory inside the volume, identified by how the
  path is written: adding a path, removing one or reordering the list keeps the
  contents of the paths you keep, and a new path, or one written differently
  (`~/.npm` instead of `/home/runner/.npm`), starts empty.
- Contents of paths that are no longer listed stay in the volume and count
  toward its capacity. Clear the volume after removing a path.

### Default volume

Without a `key`, the action attaches the default volume of the runner profile
the job runs on and the repository. Jobs on another profile get their own
default volume. Use a named `key` for directories that jobs on several profiles
should share.

Each saved copy replaces the whole volume, so the last saved copy wins. Give
workflows that save at the same time separate keys, and keep each workflow's
directories in one volume.

### Volume size

`size` sets the volume's total capacity, from `1gb` to `100gb`. Without it, a
new volume starts at `20gb` and an existing volume keeps its capacity.

- A larger size grows the volume, keeping its contents, from its next job.
- A smaller size applies after the volume is next cleared or expires.
- When workflows ask for different sizes of one key, the largest applies.
  Declare each key's size in one place.
- Sizes above `20gb` may not be enabled for every account yet. Runner images
  without size support attach the volume at its current size and warn.

### Choosing which branches save

Account administrators configure **Save cache from** on each runner profile under
**Runners → Profiles**. The settings apply to every custom volume attached by
GitHub Actions jobs that run on the profile, including volumes created later.

By default every successful job from the repository saves its changes. Turn on
**Limit to specific branches** to save only from some branches:

- **Default branch** lets jobs on each repository's default branch save. Turn it
  off to save only from the additional branches.
- **Additional branches** holds up to 20 branch names that also save. `*`
  matches any characters, so `release/*` covers `release/1.0`.

Successful push, schedule and manual-dispatch jobs, and pull requests from the
same repository, save their changes when their branch matches. On push and
manual-dispatch runs, a tag with a matching name also matches.

Fork pull requests and `pull_request_target` never save. Buildkite, GitLab and
built-in macOS volume policies are unchanged. Narrowing these settings or deleting
the profile revokes pending saves they no longer allow; a deleted profile falls
back to saving from every branch. Additions apply to new volume attachments. A
job that doesn't change a volume leaves the saved version in place.

## Releases

The public installation is `tuist/cache-volume@v1`; pin an immutable release
commit when stronger reproducibility is needed. `v1.x.y` tags are immutable;
`v1` automatically follows the latest release in that major version. The
`SOURCE_COMMIT` file records the monorepo source.

The monorepo's **Cache Volume Integrations** workflow tests and packages pull
requests. Relevant changes merged to `main` automatically release the GitHub
action, Buildkite plugin and GitLab template together. The existing
`release:check` / git-cliff machinery derives their shared semantic version;
there is no version to enter or routine manual dispatch. A no-input dispatch
recovers incomplete releases from their original published `SOURCE_COMMIT`,
even after `main` advances. Later changes are released in a follow-up run.
See the monorepo's
[release implementation](https://github.com/tuist/tuist/tree/main/ci/cache-volume).

Distribution repositories need a `main` branch and write access for
`TUIST_RELEASE_GITHUB_TOKEN` as a one-time setup. Publishing the wrappers does
not enable cache volumes on the fleet; storage rollout is independent.

On Linux, paths are mounted as ordinary directories, so tools can use their usual locations
such as `deps`, `_build`, and `node_modules`. Keep your normal `.gitignore` rules.
Each action call attaches one volume. List several paths to keep them in the same volume; see
[Several directories in one volume](#several-directories-in-one-volume).

On macOS, targets are attached as symlinks. Cache download directories such as `~/.npm`
or `~/.gradle/caches`; `node_modules` is rejected because npm replaces symlinks.
Other tools that replace their cache directory are also incompatible. For a
workspace path, ignore the link without a trailing slash (for example `.gradle`,
not `.gradle/`, in `.gitignore`). Each path must be a single line without control
characters.

On macOS, use a macOS runner profile. Native jobs are supported; Linux container
examples do not apply to macOS. Volumes mount in the macOS guest, so a separate
Docker VM does not inherit them. Built-in Tuist and Xcode caches stay automatic;
custom volumes use separate empty directories and platform-specific identities.
