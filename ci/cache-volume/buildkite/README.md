# Tuist cache volumes for Buildkite

Attach one or more private persistent directories on a Tuist Linux runner:

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
The installed client reports warm/cold reuse in the job log and Tuist dashboard.

Each volume starts at 20 GB. It is scoped to your Tuist account, immutable
Buildkite organization and pipeline, repository URL, architecture and execution
UID. Renaming a pipeline preserves its data; changing its repository URL starts
a separate cache. Concurrent jobs receive private copies. Idle data expires
after seven days without a mount.

Only successful default-branch webhook or scheduled builds without a pull
request or tag save their changes. API, manually triggered, PR and other branch
builds can read but cannot save. Eligibility comes from Buildkite's server API,
not plugin options or shell variables. Saving happens after the job and its
writers have been torn down, not in a post-command hook.

Requires a Tuist Linux fleet with cache volumes enabled, the installed
`tuist-cache-volume` client, Bash, jq and a current Buildkite agent providing
`BUILDKITE_PLUGIN_CONFIGURATION` (included in Tuist's image).
An unavailable volume falls back to an ordinary empty directory; invalid
arguments or a nonempty target fail the hook. Caches are disposable, not storage
for secrets or irreplaceable data.

This integration targets native Buildkite commands. Docker-plugin commands
require the private `/home/runner/work/_tuist_cache` root mapped to that same path
in the child container, in addition to the checkout: cache targets are symlinks.
Automatic Docker-plugin wiring is not included, and that configuration needs
its own fleet smoke test before use. macOS support is separate.

Targets are attached as symlinks. Cache download directories such as `~/.npm`
or `~/.gradle/caches`; `node_modules` is rejected because npm replaces symlinks.
Other tools that replace their cache directory are also incompatible. For a
workspace path, ignore the link without a trailing slash (for example `.gradle`,
not `.gradle/`, in `.gitignore`). Paths must be a single line without control
characters; use a plain YAML string instead of `path: |`.
