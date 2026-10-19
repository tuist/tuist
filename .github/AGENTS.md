# GitHub automation

Workflows live in `workflows/`, reusable actions in `actions/`, and supporting
scripts in `scripts/`. Changes to privileged workflows must keep contributor
content separate from executable code.

Helm CI also watches hosted dashboard changes. Monitoring cost-control tests
start the production Alloy image to compile log selectors, exercise rendered
remote-write rules against a local Prometheus receiver, and check all migrated
latency queries across mixed-version rollout states. These checks need no cloud
credentials and must never write to the production telemetry destinations.

The existing runner-image release workflow runs the portable TCC report tests
on PRs with read-only permissions and without persisted checkout credentials
or the release token. Release planning is disabled on PRs and depends on the
tests on release events. PR concurrency must not block release serialization.

UI evidence for pull request discussions lives in `screenshots/`. Capture the
actual UI with demo data and link images using immutable commit URLs.

The app's device-build job generates with `--configuration Release` to match its
Release archive. Default Debug binary-cache hits cannot be optimized by the
archive's Release setting and make the bundle-size check depend on cache warmth.
Keep simulator build/test generation on its normal configuration.

The xcresult processor follows the newest stable runner Xcode, not beta or
RC toolchains. Its matching macOS + Xcode base must be published before release.

Stable cache certificate readiness is an operator bootstrap check documented in
`infra/cache-dns/README.md`, not a gate on routine server deployments. The Kura
controller verifies TLS before advertising stable endpoints.

The runners-controller release publishes both the controller and cache-volume
agent under the same version. Its release tag requires both images to exist;
managed production selects that agent version and provisions host cache storage
through Helm, without a separate human kubectl elevation.

## Atlas native

`workflows/atlas-mobile.yml` builds Android, iOS and the Rust CLI through Once
using `actions/atlas-native/` (see its `AGENTS.md`). Fork jobs have no OIDC permission
and use only the local cache. Trusted builds use the `tuist/atlas-mobile` cache
when authentication succeeds. Main builds publish the tested artifacts to the
private Tuist project's `nightly` preview track after distinct build, test and
language-specific lint jobs pass; pull requests never publish. The single
`atlas-mobile.yml` pipeline's automatic path filters include only `atlas-native/**`
and all jobs skip draft pull requests. Rust auth dependencies are resolved during
Once graph loading, so SwiftLint jobs install Rust as well as SwiftLint/Once.
The composite materializes locked third-party sources before graph validation;
core test jobs run both navigation and authentication suites.
Mobile artifacts are debug Android APKs and
arm64 iOS simulator bundles, not store releases. The CLI is uploaded as a
host-labeled archive that preserves its executable permission, not a Tuist preview.
The Tuist project must be connected to `tuist/tuist` for GitHub OIDC access.

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
The smoke retains real CLI Swift package dependencies in `.build` and runs
`tuist install --force-resolved-versions` in both phases. Verify saved dependency
manifest checksums before installing on warm runs. Its key includes the runner
profile, Xcode version file, package manifest and lockfile; reuse all of them
across phases. Keep authentication outside the cached directory and do not
restore an archive cache into the same path.
Retain `~/.cache/swifterpm` in a separate volume and pass it explicitly as
`--cache-path`. A warm `.build` alone leaves SwifterPM's source cache cold and
can delegate the install back to native SwiftPM. Require both volume hits and
verify retained source manifests and registry checksum markers before installing.
Wait for both snapshots to publish before verification. Use a fresh prefix when
changing the set of retained paths; the two volumes publish independently.
Keep smoke phase, hit and writer variables out of the installer environment:
SwifterPM fingerprints manifest-visible variables, so test-control changes would
otherwise invalidate its retained manifest JSON between phases and writers.
The optional `concurrent` phase starts two warm writers on the same key. Each
writes its own marker and waits until both jobs reach the attachment barrier
before proceeding; dispatching two independent runs alone does not prove overlap.
Require both private markers to survive, inspect the shared parent and publication
outcomes, then run `verify` and compare its retained writer with the accepted HEAD.
The barrier reads only its own workflow run attempt and fails if its peer fails
or does not attach within 25 minutes. Keep it outside the timed install command.
Rerun both jobs together: a failed-job-only retry cannot prove overlap with a
writer from an earlier attempt.

Kura's clients test shard also runs the portable Xcode lookup fixture lifecycle
regressions in `kura/spec/e2e/xcode_lookups_lifecycle_spec.sh`. These validate
cleanup and deletion guards without Xcode or a cache service; actual compiler
replay remains an opt-in Apple silicon test.

## SwifterPM E2E credentials

`swifterpm.yml` passes its read-only job token to the E2E task's HTTPS GitHub
credential helper. The fixtures deliberately isolate HOME and disable global/system
Git configuration, so checkout's local authentication does not reach their native
SwiftPM fetches. Keep the credential in the job environment, outside cached paths;
never persist it or extend its host scope beyond github.com.

## CLI dependency volumes

macOS jobs in `cli.yml` use the standard `tuist-macos-27-0` profile. Custom
volumes do not require the larger M4 shape. If host cache capacity is unavailable,
each attachment falls back independently to an empty job-local directory; always
run dependency installation and do not require a hit in ordinary jobs. Forks use
the same custom volumes: the runner's verified job identity authorizes attachment
without workflow credentials, and the server forbids fork publication. This is
separate from the built-in account-wide cache policy. Retained contents must be
safe for fork contributors to read. Linux and release/backport workflows have
separate toolchain and runner requirements and are not part of this migration.

Use the released `tuist/install@v1` action after tool installation and authentication.
It combines one package-relative `.build` volume with forced installation, explicit
scratch/cache paths, and symlink materialization on Tuist Runners. Other runners
use its automatic GitHub archive/copy backend. Do not add a second cache step.
The macOS native SwiftPM resolve/build commands use the same
`--cache-path "$PWD/.build/dependency-cache"`. The released CLI must include #14304
so internal manifest dumps honor that path too. Keep the existing v2 workspace
keys through the action's `cache-key` input: they include job, Xcode version and
`Package.swift`, not the lockfile. The fork acceptance job uses the acceptance-build
key so default-branch runs can seed it. Preserve fork guards for Tuist login,
setup, and enterprise sources; installation itself remains unconditional.
Keep configuration, security, and authentication outside the cache. Mise's
postinstall hook skips dependency installation on CI so it does not populate the
volume target before the action runs.

Set `TUIST_DEV_INSTANCE=1` before mise so random checkout-local development
settings do not invalidate manifest fingerprints. `Tuist.swift` uses plain
`packageManifestEnvironment: .automatic`, backed by #14162's released filtering
and separate native-resolution authentication. #14156's content-based manifest
caches reuse unchanged root and local packages across fresh checkout timestamps.
Keep platform/toolchain and application inputs visible, and always measure
fresh-runner reuse: a volume hit alone does not prove evaluation was skipped.
The historical 8.31-second result used explicit exclusions and a larger runner;
it is not a benchmark of this single-volume layout or the automatic policy.

Ordinary PR jobs consume private snapshots without publishing. Successful
permitted jobs seed the new keys; measure warm jobs only after publication.
Always run installation on hits to validate the current lockfile. Track queue
time separately, and distinguish actual attachment/hits from empty-directory
fallback. Retaining only an external source/native-manifest cache is possible,
but rebuilds workspace state and manifest JSON; benchmark it separately before
changing the retained layout.

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
restore-mix-cache=false callers and its `deps` callers, which attach only the
`deps` volume. Do not add volume-specific composite wrappers.

## Server test sharding

`server.yml` compiles the test build once and creates separate four-shard plans
for current and oldest-supported ClickHouse, with references scoped to the GitHub
run, attempt, and variant. Each shard owns fresh PostgreSQL and ClickHouse databases.
Only the build job compiles, so it stays on `tuist-linux-large` while the shards
run on the default `tuist-linux` shape. Run `mix compile --warnings-as-errors`
through the server's bootstrap-aware compile alias before discovering
`tuist.test.build`: discovering an unloaded SDK task on a cold checkout lets
Mix compile all dependencies before Tuist can restore or observe the cache.
Bootstrap `tuist_ex` and its dependencies with `mix deps.compile tuist_ex --include-children`, then download with `mix tuist.test --prepare-only`; include children for coverage completion as well so cold jobs have gRPC/Protobuf available.
`tuist_ex` exchanges the job's GitHub OpenID Connect token itself, so there is no
login step. Run `db:reset`
in a separate process before `mix tuist.test --no-download --warnings-as-errors`,
so migration regression tests do not redefine modules already loaded by setup.
Date the shard's checkout to the commit time before `db:reset`: a checkout newer
than the downloaded build makes Mix treat `noora` and `tuist_common` as changed and
recompile the app.
The build job and shards attach only the `deps` volume (`restore-mix-cache: deps`):
the build job compiles from an empty `_build` and the shards download theirs. They
also pass `mise-cache: "false"`: installing Erlang and Elixir from scratch is
faster than restoring mise-action's archive. Postgres service health checks poll
every second as the `postgres` role; probing as `root` logs a FATAL on every check.
In CI, `db:reset` creates, migrates and lists migrations in one Mix process.
Take shard references from the build job's outputs, not the current run attempt,
so rerunning only failed jobs reuses the original plan. Keep distinct `--scheme`
labels for ClickHouse variants so their outcomes are not treated as flaky reruns.
Keep `TUIST_DEV_ALL_LOCALES=1` in both phases. Fork pull requests run both unsharded
variants without Tuist authentication or `id-token: write`, like the CLI and
Gradle fork fallbacks. The explicitly named unsharded fallback also runs both variants when the build-plan job fails, without changing that job's failure status. Never silently fall back to the whole suite inside an authenticated shard.

On push to main, the current ClickHouse shards also run with `--cover`,
reporting the server's coverage to `tuist/server`,
and `coverage-complete` then runs `mix tuist.coverage.complete`. The build
job plans them with `mix tuist.test.build --cover`, which instruments the
build for native coverage, so the shards count without compiling every
module for `cover`. Keep coverage
off pull requests, the merge queue, the floor shards and the unsharded
fallback, and never let it fail the run. Xcode coverage lives in `coverage.yml`,
whose runs read the binary cache: `cli.yml`'s cache job on main warms the plain
variant and then the coverage variant (`tuist cache --coverage`), which the runs
with `-enableCodeCoverage YES` look up. Every `tuist test` that uploads coverage
passes `--derived-data-path`, because the coverage export reads the test
products and the profile from derived data, and the result-bundle fallback it
takes without one never covers cached code.

## Restore drills

CNPG restore drills resolve production to namespace `tuist`, not `tuist-production`; staging and canary retain their prefixed namespaces. Validate the resolver with `python3 .github/scripts/cnpg-restore-drill.test.py` without credentials. Recovery clusters are isolated and must never archive into or delete the source backup path. Use a run-scoped disposable StorageClass cloned from the source data volume's provisioning settings, with `Delete` reclamation and no default-class annotation. Never change the source class or existing volumes. Teardown must target only the run's `pg-restore-drill-*` resources, use foreground cluster deletion, verify PVC/PV removal, and propagate failures rather than silently leaving copied data. Previously retained drill volumes require separate human-authorized cleanup.

## CLI Cargo cache packaging

Cargo compilation caching is implemented in Swift inside `tuist`. Do not package a separate Cargo cache executable or import an external cache engine. The existing Xcode CAS plugin and proxy remain separate Rust artifacts.

## CLI Linux builds

The Linux release ships a static musl binary built with the Swift Static Linux SDK. The PR `Linux Build` job in `cli.yml` compiles against the same SDK, installed through `mise/utilities/install_static_linux_sdk.sh` (shared with `mise/tasks/cli/bundle-linux.sh`), so it catches code that only builds against glibc. Its `.build` cache key uses the `linux-cli-musl-` prefix to stay separate from the glibc cache used by `Linux Unit Tests`, which keeps running on glibc.

## CLI release manifests

`cli-build-publish.yml` signs the final CLI archives with Packslip before publishing
any release channel. Keep signing in the checkout-free, read-only `sign-cli` job,
without the workflow-level release token; the existing publisher uploads the bundle.
Describe `tuist.zip` as universal macOS. Let Packslip infer Linux libc requirements
from the archived executables: current builds are static, but older backport
bundlers may produce dynamic binaries. Never override libc with `any`.
Record `inputs.ref`, not the caller's `github.sha`, as the source commit. Builds
do not currently publish provenance, so keep `attest: false` until provenance
can truthfully identify each archive's build source.

`cli-release-tests.yml` installs the CLI from the same pinned Packslip action and
runs `bash .github/scripts/cli-packslip.test.sh`. The tests use `yq`, `jq`, offline
keys, and generated ELF archives; they need neither OIDC nor release-write credentials.
They also require every release-channel caller to use the shared publisher and
keep signing unconditional across channels.

## Atlas releases

Atlas releases publish the image and standalone Helm chart with the same version, plus a Compose bundle. Managed deployment consumes the published chart with an explicit production overlay; publishing must not require cluster credentials. Deployment validation pins Helm, mikefarah yq, and jq and runs the rendering and fake-kubectl retirement checks before the image build. Managed deployment checks live legacy namespace retention after stuck-release recovery, because rollback can remove its retention annotation. Keep that read-only guard before upgrades that disable the legacy sandbox objects. The release-list arguments must remain compatible with the pinned Helm version; fake release-state tests also validate them against the real CLI without cluster access. After rollout and readiness, the managed release smoke test requires the public root to redirect signed-out visitors to `/login`, so a healthy but outdated or misrouted application cannot pass.

## Cloudflare configuration

`workflows/cloudflare-config-tests.yml` runs the crawler-exemption scope regressions without credentials on pull requests and main changes. These tests do not validate Cloudflare's API expression parser or modify the live zone.

## SwifterPM diagnostics

The SwifterPM E2E workflow probes public Git HTTP status and isolated Git access after a failure. Keep probes credential-free and do not log authorization headers or change the test result.

## CodeQL

`workflows/codeql.yml` replaces GitHub's CodeQL default setup. Default setup
must stay disabled in the repository settings, or uploads from this workflow
are rejected.

- Runner-controller checks, image builds and release path filters include the shared `infra/runner-cache` module.

## CLI Linux release

`release-cli-linux` in `workflows/cli-build-publish.yml` builds both Linux
tarballs on `tuist-linux-large` inside `swift:6.2`. The fleet is amd64-only,
so aarch64 is cross-compiled through the static Linux SDK and the bundle
script checks the architecture and that the binary is static before packaging.
`mise/utilities/install_static_linux_sdk.sh` (shared with the PR `Linux Build`
job) hides the host's zlib and libxml2 `.pc` files: SwiftPM's pkg-config
parser keeps the host's `/usr/lib/<host-triple>` from them, and a cross link
then fails on the host's archives. Do not point SwiftPM at the SDK's own `.pc`
files instead; SwiftPM rewrites any `-I`/`-L` path containing `.sdk`, which
corrupts every path inside the static SDK's `musl-*.sdk/<arch>` root.
Keep one matrix job per architecture: per-architecture compile time is
dominated by single-threaded release modules, so a shared job serializes them.
`.build` is a cache volume keyed by architecture and Swift version, and the
SwiftPM download cache is a second, shared one. A fresh checkout still
recompiles every first-party module; the volume only spares the pinned
third-party graph. Mounted cache directories are emptied in place, never
removed. Keep the registry proxy, the resolve retry and the
`cli-linux-<arch>-artifacts` names that `publish-cli` merges.

## Generated-project dependency installation

`actions/install/` implements the standalone `tuist/install` action; see
[its guidance](actions/install/AGENTS.md). It automatically uses a custom workspace
volume when the runner client is available, or GitHub archives otherwise, with
pinned dependency installation using the project's already-installed CLI.
`workflows/install-action.yml` tests/packages changes and automatically publishes
relevant main changes through the `install-action` release component after tests
pass. Bootstrap the distribution repository and release credential first.
Recover an unrecorded distribution from its original SOURCE_COMMIT before
publishing newer source; never replace an immutable version.
