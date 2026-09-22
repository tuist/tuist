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

Or copy `cache-volume.yml` into your repository as
`.gitlab/tuist-cache-volume.yml`, then compose its reusable snippet:

```yaml
include:
  - local: .gitlab/tuist-cache-volume.yml

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

You may also include the raw file from this repository at an immutable commit
using GitLab's `include:remote`, or mirror it to your GitLab instance.
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
The GitLab instance must expose the job API's `source` field and permit branch
listing with that token. Missing source metadata never grants save permission;
API failure declines attachment. Predefined-looking `CI_*` variables are not
used to grant permission. Successful default-branch push, schedule and web
pipelines can save; tags, merge requests, child and other pipelines cannot.
Saved changes become available only after the job and local writers are gone.

Tuist embeds GitLab Runner's shell executor in the isolated Linux runner.
A job's `image:` does not select a Docker executor. Docker child containers
need explicit private-root mounts and separate validation. macOS support is
not included. Caches must not contain secrets or irreplaceable data.
