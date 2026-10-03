# Provider cache-volume entry points

Buildkite's distributable plugin is in `buildkite/`; GitLab's reusable hidden
job is in `gitlab/`. Both call the preinstalled Linux client. GitHub's action
lives in `../../.github/actions/cache-volume/`.

Never accept trust, provider identity or publication decisions from workflow
inputs. The server resolves the assigned session against provider APIs.
Wrappers only pass quoted key/path arguments and propagate client failures;
they never implement publication hooks or download binaries.

Run the Bash suites `integrations_test.sh`, `publish_test.sh`,
`release_check_test.sh`, and `prepare-release_test.sh` in this directory.
They use Git, jq and git-cliff; keep
tests and fixtures in Bash, consistent with runner-image and release scripts.
Keep the Buildkite package self-contained and hooks executable.
The cache-volume-action workflow tests and packages all three integrations and
releases them automatically on relevant main pushes, using the `cache-volume`
component in `release:check` and `cliff.toml`. All distributions share one version.
`publish.sh` owns atomic per-repository pushes and identical-content retries;
never overwrite an immutable tag. Record the monorepo release only after all
three distributions succeed. Distribution repositories/token access are a
one-time setup; publishing wrappers does not enable the fleet.
GitLab's direct command and vendorable template must work on self-managed
instances without a GitLab.com-only Catalog dependency.

`prepare-release.sh` recovers any incomplete distribution version from its original
SOURCE_COMMIT before building a new release. Validate against local bare remotes
with a rejected intermediate push, advanced main and deleted old artifacts.
