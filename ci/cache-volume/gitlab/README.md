# Tuist cache volumes for GitLab CI

Use the installed client before dependency tools populate a directory:

```yaml
test:
  tags: [tuist-linux]
  variables:
    GRADLE_USER_HOME: "$CI_PROJECT_DIR/.gradle"
  before_script:
    - tuist-cache-volume --key gradle-dependencies --path .gradle
  script:
    - ./gradlew test
```

Or include the automatically released template and compose its reusable snippet:

```yaml
include:
  - remote: https://raw.githubusercontent.com/tuist/cache-volume-gitlab/v1/cache-volume.yml

test:
  tags: [tuist-linux]
  variables:
    TUIST_VOLUME_KEY: gradle-dependencies
    TUIST_VOLUME_PATH: .gradle
    GRADLE_USER_HOME: "$CI_PROJECT_DIR/.gradle"
  before_script:
    - !reference [.tuist-cache-volume, before_script]
    - echo "Existing setup commands go here"
  script:
    - ./gradlew test
```

Pass `--path` once per directory, or set `TUIST_VOLUME_PATH` to one path per
line, to keep several directories in the same volume. Blank lines and
surrounding whitespace are ignored. Pass `--size` or set `TUIST_VOLUME_SIZE` to
set the volume's capacity.

```yaml
lint:
  tags: [tuist-linux]
  before_script:
    - tuist-cache-volume --key python-tools --size 5gb --path ~/.cache/pip --path ~/.cache/pre-commit
  script:
    - pre-commit run --all-files
```

```yaml
lint:
  tags: [tuist-linux]
  variables:
    TUIST_VOLUME_KEY: python-tools
    TUIST_VOLUME_SIZE: 5gb
    TUIST_VOLUME_PATH: |
      ~/.cache/pip
      ~/.cache/pre-commit
  before_script:
    - !reference [.tuist-cache-volume, before_script]
  script:
    - pre-commit run --all-files
```

| Variable | Contract |
| --- | --- |
| `TUIST_VOLUME_KEY` | Required stable volume name. Keys starting with `tuist-` are reserved. |
| `TUIST_VOLUME_PATH` | Required. Up to 16 absent or empty directories, one per line. |
| `TUIST_VOLUME_SIZE` | Optional capacity, a whole number of GB from `1gb` to `100gb`, such as `50gb`. New volumes start at `20gb` without it. |

- All paths share the volume's capacity and are restored and saved together.
- Paths in one volume must not contain each other.
- A single path keeps the volume's contents when it changes. With several
  paths, each has its own directory inside the volume, identified by how the
  path is written: adding a path, removing one or reordering the list keeps the
  contents of the paths you keep, and a new path, or one written differently
  (`~/.npm` instead of `/home/runner/.npm`), starts empty.
- Contents of paths that are no longer listed stay in the volume and count
  toward its capacity. Clear the volume after removing a path.
- Each saved copy replaces the whole volume, so the last saved copy wins. Give
  jobs that save at the same time separate keys.
- A larger size grows the volume, keeping its contents, from its next job. A
  smaller one applies after the volume is next cleared or expires. When jobs
  ask for different sizes of one key, the largest applies.
- Sizes above `20gb` may not be enabled for every account yet. Runner images
  without size support attach the volume at its current size; the template
  warns.

Relevant changes merged to the monorepo’s `main` automatically publish
`tuist/cache-volume-gitlab` alongside the GitHub action and Buildkite plugin,
using the same semantic version. `v1` follows the latest release in that major
version; replace it with an immutable `v1.x.y` tag or full release commit to pin
the template. `SOURCE_COMMIT` records its monorepo source.

You can also vendor `cache-volume.yml` and use `include:local`, or mirror it to
your GitLab instance. Until the first release, use a reviewed monorepo commit.
No GitLab.com-only Catalog component is required. For separate volumes, call the
client once per key (maximum eight per job). Keep keys stable,
for example `gradle-dependencies`: a key is a volume name, not a content hash,
so do not include lockfile, tool-version or commit hashes. A new key starts empty.

Volume targets must be absent or empty. Remove overlapping `cache:paths` or
artifact restoration paths; keep unrelated archive caches. GitLab restores
archives and artifacts before `before_script`. Tuist's existing archive cache
integration remains independent.

Volumes are scoped by Tuist account, GitLab instance, immutable project ID, key,
architecture and UID. Project renames retain data; another instance with the
same project ID cannot reuse it. Each job receives a private copy, with `20gb`
capacity unless a size is set, and seven-day idle expiration; when saved contents reach 80% of
capacity and a job runs out of space on them, the next job starts empty. The client logs warm/cold reuse and the
Tuist dashboard records it. Unavailable storage falls back to an empty directory;
invalid inputs and nonempty targets fail the step.

The server verifies the current job through `GET /job` and its exact branch
through `GET /projects/:id/repository/branches`, using the acquired job token.
The GitLab instance must expose the job API's `pipeline.source` field (or the
top-level `source` when the nested field is absent) and permit branch
listing with that token. Missing source metadata never grants save permission;
API failure declines attachment. Predefined-looking `CI_*` variables are not
used to grant permission. Successful push, schedule and web pipelines on any
branch can save, narrowed by the runner profile's **Save cache from** setting;
tags, merge requests, child and other pipelines cannot.
Saved changes become available only after the job and local writers are gone.

Tuist embeds GitLab Runner's shell executor in the isolated Linux or macOS runner.
A job's `image:` does not select a Docker executor. Docker child containers
need explicit private-root mounts and separate validation. macOS support is
not included. Caches must not contain secrets or irreplaceable data.

Linux targets are bind-mounted as ordinary directories. On macOS, targets are
attached as symlinks. Cache download directories such as `~/.npm`
or `~/.gradle/caches`; `node_modules` is rejected on macOS because npm replaces symlinks.
Other tools that replace their cache directory are also incompatible on macOS.
For a macOS
workspace path, ignore the link without a trailing slash (for example `.gradle`,
not `.gradle/`, in `.gitignore`). Each path must be a single line without control
characters.

On macOS, use a macOS runner profile. Native jobs are supported; Linux container
examples do not apply to macOS. Volumes mount in the macOS guest, so a separate
Docker VM does not inherit them. Built-in Tuist and Xcode caches stay automatic;
custom volumes use separate empty directories and platform-specific identities.
