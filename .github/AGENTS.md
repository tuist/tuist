# GitHub automation

Workflows live in `workflows/`, reusable actions in `actions/`, and supporting
scripts in `scripts/`. Changes to privileged workflows must keep contributor
content separate from executable code.

The runners-controller release publishes both the controller and cache-volume
agent under the same version. Its release tag requires both images to exist;
managed production selects that agent version and provisions host cache storage
through Helm, without a separate human kubectl elevation.

## Community notifications

`workflows/community-notifications.yml` sends new community issues and PRs to
Slack. Filtering and payload construction live in
`scripts/community-notifications.cjs`; setup and operational limitations are
documented in `COMMUNITY_NOTIFICATIONS.md`.

- Exclude `company` and `external` team members, GitHub bots, and explicitly
  listed legacy automation accounts. Do not use repository association as an
  employment signal.
- Membership lookup errors must fail visibly, not produce staff notifications.
- The privileged PR workflow must only check out trusted event code, never a
  PR head or merge ref. Keep contributor text in plain-text Slack blocks.
- Validate changes with `node --test scripts/community-notifications.test.cjs`
  from this directory and `actionlint workflows/community-notifications.yml`.

Cache-volume distribution recovery uses the original immutable source commit from
a partial release; finish that version before dispatching a release of newer main
changes. Never substitute new contents beneath an existing distribution tag.

Linux Gradle tests and runner-controller tests use the released `tuist/cache-volume@v1`
action with stable keys and isolated paths outside checkout. Gradle uses one
home volume and resolves GRADLE_USER_HOME with readlink before setup to avoid
Gradle 9.2 Kotlin DSL symlink classpath failures. Disable archive
caching for those same paths; keep Go test result reuse disabled with `-count=1`.
The manual Linux Cache Volume Benchmark compares baseline, cold and warm runs
at an identical reviewed source SHA/profile pinned in the workflow (never a
dispatch-selected code ref that could publish untrusted cache contents). Warm runs must prove mounted volume hits and
retained source markers; never count the client's cold fallback as a warm result.
Run cold/warm from the default branch so successful cold jobs can publish, and
wait for publication before starting warm jobs. Keep benchmark keys separate
from normal CI, and record attachment and workload times separately.

## Tuist Elixir package

`tuist-ex.yml` runs separate compilation, documentation, test, formatting,
and package jobs. Compilation covers the minimum and current supported Elixir
versions. The workflow is reused by `tuist-ex-release.yml` before publication.
Releases run only from `main`, serialize publishing, and use the shared
`release:check` registry with the `tuist-ex@` tag prefix. The existing
`HEX_API_KEY` secret used by Noora must be able to publish `tuist_ex`.

## Bazel and Mix cache volumes

`scripts/cache-volumes/bazel.sh` configures Kura's repository downloads and disk cache,
not its output base, Bazel server or remote credentials. Keep Tuist remote cache
setup in trusted jobs; fork jobs use the same per-task volume key without OIDC.
Bazel performs idle disk-cache GC with a 12 GiB target and seven-day age limit;
this is a soft cleanup target within the 20 GB volume, not a build-time quota.
See [the script instructions](scripts/cache-volumes/AGENTS.md).

`scripts/cache-volumes/mix.sh` keeps deps and _build together under readable project/job
keys. An internal identity marker checks Elixir/ERTS versions and the exact lockfile
hash; incompatible private build state is discarded before reuse. Install tools first and attach before
fetching dependencies. Never retain ~/.hex or authentication configuration.
Preserve setup-server-mix's explicit restore-mix-cache=false callers.
Workflows call the released action directly, then configure their tool; avoid extra
volume composite wrappers. See [the script instructions](scripts/cache-volumes/AGENTS.md).

`workflows/linux-build-cache-benchmark.yml` compares fixed-source Kura binary and
Registry production builds with identical helpers/profile across baseline, cold
and warm phases. Remote caching is opt-in. Without it, these numbers only measure
local reuse. To compare against remote caching, seed with remote_cache=true and
phase=cold, then run baseline (remote-only, empty local state) and warm (remote
plus volumes). Remote setup must succeed; the remote-only build must report hits.
The benchmark mirror uses its existing tuist/mastodon OIDC project on the same
account's cache service. Keep credentials and generated .bazelrc.tuist outside
volumes. Record remote/disk action hits and attachment overhead separately.
