# Tuist cache volumes for Buildkite

Attach one or more private persistent directories on a Tuist Linux or macOS runner:

```yaml
steps:
  - label: Test
    agents:
      queue: tuist-linux
    plugins:
      - tuist/cache-volume#v1:
          volumes:
            - key: gradle-dependencies
              path: .gradle
    env:
      GRADLE_USER_HOME: .gradle
    command: ./gradlew test
```

Set `path` to a list to keep several directories in the same volume, and
`size` to set its capacity:

```yaml
steps:
  - label: Lint
    agents:
      queue: tuist-linux
    plugins:
      - tuist/cache-volume#v1:
          volumes:
            - key: python-tools
              size: 5gb
              path:
                - ~/.cache/pip
                - ~/.cache/pre-commit
    command: pre-commit run --all-files
```

| Field | Contract |
| --- | --- |
| `key` | Optional stable volume name. Omit it to use the default volume of the runner profile and pipeline. Keys starting with `tuist-` are reserved. |
| `path` | Required. One absent or empty directory, or a list of up to 16. |
| `size` | Optional capacity, a whole number of GB from `1gb` to `100gb`, such as `50gb`. New volumes start at `20gb` without it. |

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
  pipelines that save at the same time separate keys.
- Without a `key`, jobs on another runner profile get their own default volume, and deleting a profile clears its default volumes. Jobs on a queue that is not a Tuist runner profile need a `key`.
  Use a named `key` for directories that several profiles should share.
- A larger `size` grows the volume, keeping its contents, from its next job. A
  smaller one applies after the volume is next cleared or expires. When steps
  ask for different sizes of one key, the largest applies.
- Sizes above `20gb` may not be enabled for every account yet. Runner images
  without size support attach the volume at its current size and warn.

This plugin's distribution repository is `tuist/cache-volume-buildkite-plugin`.
Relevant changes merged to the monorepo’s `main` automatically publish it
alongside the GitHub action and GitLab template, using a shared semantic version.
`v1.x.y` tags are immutable; `v1` tracks the latest release in that major version.
Pin a release commit for reproducible pipelines. Until the first release, use a
local plugin checkout containing this directory. Fleet enablement is separate.

The pre-command hook runs after checkout. Target directories must be absent or
empty; do not restore another cache or artifact into them first. Keys support
letters, digits, dots, underscores, slashes and hyphens (maximum 200 characters,
starting with a letter or digit). Up to eight volumes can be mounted per job.
A key is a stable volume name, not a content hash: do not include lockfile,
tool-version or commit hashes. Each job starts from the latest saved contents
and your tools update them; a new key starts empty.
The installed client reports warm/cold reuse in the job log and Tuist dashboard.

Each volume starts at `20gb` unless `size` sets another capacity. It is scoped
to your Tuist account, immutable Buildkite organization and pipeline, repository
URL, architecture and execution UID. Renaming a pipeline preserves its data; changing its repository URL starts
a separate cache. Concurrent jobs receive private copies. Idle data expires
after seven days without a mount. When saved contents reach 80% of capacity
and a job runs out of space on them, the next job starts empty.

Successful webhook or scheduled builds on any branch save their changes,
including pull requests whose head is the pipeline's repository, narrowed by the
runner profile's **Save cache from** setting. Fork pull requests, tags and API
or manually triggered builds can read but cannot save. Eligibility comes from Buildkite's server API,
not plugin options or shell variables. Saving happens after the job and its
writers have been torn down, not in a post-command hook.

Requires a Tuist Linux or macOS fleet with cache volumes enabled, the installed
`tuist-cache-volume` client, Bash, jq and a current Buildkite agent providing
`BUILDKITE_PLUGIN_CONFIGURATION` (included in Tuist's image).
An unavailable volume falls back to an ordinary empty directory; invalid
arguments or a nonempty target fail the hook. Caches are disposable, not storage
for secrets or irreplaceable data.

This integration targets native Buildkite commands. Docker-plugin commands
need explicit volume mapping and mount-namespace integration so the child
container sees the attached Linux directories.
Automatic Docker-plugin wiring is not included, and that configuration needs
its own fleet smoke test before use. macOS support is separate.

Linux targets are bind-mounted as ordinary directories. On macOS, targets are
attached as symlinks. Cache download directories such as `~/.npm`
or `~/.gradle/caches`; `node_modules` is rejected on macOS because npm replaces symlinks.
Other tools that replace their cache directory are also incompatible on macOS.
For a macOS
workspace path, ignore the link without a trailing slash (for example `.gradle`,
not `.gradle/`, in `.gitignore`). Each path must be a single line without control
characters; list several paths as a YAML list instead of `path: |`.

On macOS, use a macOS runner profile. Native jobs are supported; Linux container
examples do not apply to macOS. Volumes mount in the macOS guest, so a separate
Docker VM does not inherit them. Built-in Tuist and Xcode caches stay automatic;
custom volumes use separate empty directories and platform-specific identities.
