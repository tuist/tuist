# Provider cache-volume entry points

Buildkite's distributable plugin is in `buildkite/`; GitLab's reusable hidden
job is in `gitlab/`. Both call the preinstalled Linux client. GitHub's action
lives in `../../.github/actions/cache-volume/`.

Never accept trust, provider identity or publication decisions from workflow
inputs. The server resolves the assigned session against provider APIs.
Wrappers only pass quoted key/path arguments and propagate client failures;
they never implement publication hooks or download binaries.

Run `python3 -m unittest discover -s ci/cache-volume -p '*_test.py' -v` from the
repository root. Keep the Buildkite package self-contained and hooks executable.
The cache-volume-action workflow tests and packages all three integrations and
releases them automatically on relevant main pushes, using the `cache-volume`
component in `release:check` and `cliff.toml`. All distributions share one version.
`publish.py` owns atomic per-repository pushes and identical-content retries;
never overwrite an immutable tag. Record the monorepo release only after all
three distributions succeed. Distribution repositories/token access are a
one-time setup; publishing wrappers does not enable the fleet.
GitLab's direct command and vendorable template must work on self-managed
instances without a GitLab.com-only Catalog dependency.
