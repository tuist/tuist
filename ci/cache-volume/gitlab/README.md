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

Relevant changes merged to the monorepo’s `main` automatically publish
`tuist/cache-volume-gitlab` alongside the GitHub action and Buildkite plugin,
using the same semantic version. `v1` follows the latest release in that major
version; replace it with an immutable `v1.x.y` tag or full release commit to pin
the template. `SOURCE_COMMIT` records its monorepo source.

You can also vendor `cache-volume.yml` and use `include:local`, or mirror it to
your GitLab instance. Until the first release, use a reviewed monorepo commit.
No GitLab.com-only Catalog component is required. For multiple directories, call
the client once per key/path pair (maximum eight per job).

Volume targets must be absent or empty. Remove overlapping `cache:paths` or
artifact restoration paths; keep unrelated archive caches. GitLab restores
archives and artifacts before `before_script`. Tuist's existing archive cache
integration remains independent.

Volumes are scoped by Tuist account, GitLab instance, immutable project ID, key,
architecture and UID. Project renames retain data; another instance with the
same project ID cannot reuse it. Each job receives a private copy, with 20 GB
capacity and seven-day idle expiration. The client logs warm/cold reuse and the
Tuist dashboard records it. Unavailable storage falls back to an empty directory;
invalid inputs and nonempty targets fail the step.

The server verifies the current job through `GET /job` and its exact branch
through `GET /projects/:id/repository/branches`, using the acquired job token.
The GitLab instance must expose the job API's `pipeline.source` field (or the
top-level `source` when the nested field is absent) and permit branch
listing with that token. Missing source metadata never grants save permission;
API failure declines attachment. Predefined-looking `CI_*` variables are not
used to grant permission. Successful default-branch push, schedule and web
pipelines can save; tags, merge requests, child and other pipelines cannot.
Saved changes become available only after the job and local writers are gone.

Tuist embeds GitLab Runner's shell executor in the isolated Linux or macOS runner.
A job's `image:` does not select a Docker executor. Docker child containers
need explicit private-root mounts and separate validation. macOS support is
not included. Caches must not contain secrets or irreplaceable data.

Targets are attached as symlinks. Cache download directories such as `~/.npm`
or `~/.gradle/caches`; `node_modules` is rejected because npm replaces symlinks.
Other tools that replace their cache directory are also incompatible. For a
workspace path, ignore the link without a trailing slash (for example `.gradle`,
not `.gradle/`, in `.gitignore`). Paths must be a single line without control
characters; use a plain YAML string instead of `path: |`.

On macOS, use a macOS runner profile. Native jobs are supported; Linux container
examples do not apply to macOS. Volumes mount in the macOS guest, so a separate
Docker VM does not inherit them. Built-in Tuist and Xcode caches stay automatic;
custom volumes use separate empty directories and platform-specific identities.
