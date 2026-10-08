# GitHub automation

Workflows live in `workflows/`, reusable actions in `actions/`, and supporting
scripts in `scripts/`. Changes to privileged workflows must keep contributor
content separate from executable code.

UI evidence for pull request discussions lives in `screenshots/`. Capture the
actual UI with demo data and link images using immutable commit URLs.

The app's device-build job generates with `--configuration Release` to match its
Release archive. Default Debug binary-cache hits cannot be optimized by the
archive's Release setting and make the bundle-size check depend on cache warmth.
Keep simulator build/test generation on its normal configuration.

Stable cache certificate readiness is an operator bootstrap check documented in
`infra/cache-dns/README.md`, not a gate on routine server deployments. The Kura
controller verifies TLS before advertising stable endpoints.

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
home volume mounted at GRADLE_USER_HOME. Disable archive
caching for those same paths; keep Go test result reuse disabled with `-count=1`.

## Tuist Elixir package

`tuist-ex.yml` runs separate compilation, documentation, test, formatting,
and package jobs. Compilation covers the minimum and current supported Elixir
versions. The workflow is reused by `tuist-ex-release.yml` before publication.
Releases run only from `main`, serialize publishing, and use the shared
`release:check` registry with the `tuist-ex@` tag prefix. The existing
`HEX_API_KEY` secret used by Noora must be able to publish `tuist_ex`.

The optional `custom_cache_apfs` staging smoke input runs the candidate shared
cache lifecycle and real APFS tests in a staging macOS runner. It validates native
filesystem behavior, not a deployed host/mailbox/server rollout. Keep that
limitation explicit when reporting smoke results.
`macos-cache-volumes-smoke.yml` exercises the deployed action, guest APFS mount
and teardown/publication path on main. Run seed, then verify with the same key
after publication; fail then verify checks that failed-job writes are discarded.
Require the symlink/APFS mount and warm hit so a cold fallback cannot pass.
## Bazel and Mix cache volumes

Kura's `.bazelrc` configures repository downloads and disk action caching under
`~/.cache/tuist/bazel` on Linux, not its output base or remote credentials. CI
attaches that directory with the released action. Keep Tuist remote cache setup
in trusted jobs. Idle disk-cache GC has a 12 GiB target and seven-day age limit;
this is a soft cleanup target within the 20 GB volume, not a build-time quota.

Mix jobs attach their ordinary `deps` and `_build` directories with separate
readable project/job keys. Mix owns compiler and dependency invalidation; do not
add lockfile-hash keys, compatibility-marker scripts or physical-path rewrites.
Always run dependency resolution and compilation on hits. Never retain ~/.hex
or authentication configuration. Preserve setup-server-mix's explicit
restore-mix-cache=false callers. Do not add volume-specific composite wrappers.

## Server test sharding

`server.yml` compiles the test build once and creates separate four-shard plans
for current and oldest-supported ClickHouse, with references scoped to the GitHub
run, attempt, and variant. Each shard owns fresh PostgreSQL and ClickHouse databases.
Bootstrap only `tuist_ex`, authenticate with `mix tuist.login` using GitHub
OpenID Connect, and download with `mix tuist.test --prepare-only`. Run `db:reset`
in a separate process before `mix tuist.test --no-download --warnings-as-errors`,
so migration regression tests do not redefine modules already loaded by setup.
Take shard references from the build job's outputs, not the current run attempt,
so rerunning only failed jobs reuses the original plan. Keep distinct `--scheme`
labels for ClickHouse variants so their outcomes are not treated as flaky reruns.
Keep `TUIST_DEV_ALL_LOCALES=1` in both phases. Fork pull requests run both unsharded
variants without Tuist authentication or `id-token: write`, like the CLI and
Gradle fork fallbacks. The explicitly named unsharded fallback also runs both variants when the build-plan job fails, without changing that job's failure status. Never silently fall back to the whole suite inside an authenticated shard.

## Restore drills

CNPG restore drills resolve production to namespace `tuist`, not `tuist-production`; staging and canary retain their prefixed namespaces. Validate the resolver with `python3 .github/scripts/cnpg-restore-drill.test.py` without credentials. Recovery clusters are isolated and must never archive into or delete the source backup path. Use a run-scoped disposable StorageClass cloned from the source data volume's provisioning settings, with `Delete` reclamation and no default-class annotation. Never change the source class or existing volumes. Teardown must target only the run's `pg-restore-drill-*` resources, use foreground cluster deletion, verify PVC/PV removal, and propagate failures rather than silently leaving copied data. Previously retained drill volumes require separate human-authorized cleanup.

Atlas releases publish the image and standalone Helm chart with the same version, plus a Compose bundle. Managed deployment consumes the published chart with an explicit production overlay; publishing must not require cluster credentials. Deployment validation pins Helm, mikefarah yq, and jq and runs the rendering and fake-kubectl retirement checks before the image build. Managed deployment checks live legacy namespace retention after stuck-release recovery, because rollback can remove its retention annotation. Keep that read-only guard before upgrades that disable the legacy sandbox objects.

## CodeQL

`workflows/codeql.yml` replaces GitHub's CodeQL default setup. Default setup
must stay disabled in the repository settings, or uploads from this workflow
are rejected.

- Runner-controller checks, image builds and release path filters include the shared `infra/runner-cache` module.
