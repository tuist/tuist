# GitHub automation

Workflows live in `workflows/`, reusable actions in `actions/`, and supporting
scripts in `scripts/`. Changes to privileged workflows must keep contributor
content separate from executable code.

Helm CI also watches hosted dashboard changes. Monitoring cost-control tests
start the production Alloy image to compile log selectors, exercise rendered
remote-write rules against a local Prometheus receiver, and check all migrated
latency queries across mixed-version rollout states. These checks need no cloud
credentials and must never write to the production telemetry destinations.
The Helm render job also runs `infra/helm/tuist/test-cluster-cookie.py` offline:
check all managed environment cookie references and Secret ownership without
reading 1Password or logging rendered cookie values.

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

`workflows/cache-dns.yml` plans `infra/cache-dns/zone.yaml` on pull requests and
applies it on `main`, assuming roles from `infra/cache-dns/deploy-role.yaml`. The
pull-request role can create change sets but never execute them, so a modified
workflow on a branch still cannot change the zone.

The runners-controller release publishes both the controller and cache-volume
agent under the same version. Its release tag requires both images to exist;
managed production selects that agent version and provisions host cache storage
through Helm, without a separate human kubectl elevation.

Server CI's Format job runs `scripts/server-clickhouse.test.sh` against the real local/CI launcher with stubbed ClickHouse/HTTP commands and child-process-only file limits. Cover low soft limits, already-raised limits, restricted hard ceilings, unsupported raises and the already-running fast path. The launcher raises ClickHouse's soft limit to its available hard limit before spawning it; do not replace this safeguard with seed retries or reduce seed coverage to hide file-descriptor exhaustion.

## Server production deployment

`workflows/server-production-deployment.yml` decides whether a push deploys by
diffing the deployable paths from the commit production last deployed, not from
the push's `before`. Queued runs collapse, so a deployable commit whose run was
replaced by a non-deployable push must still deploy. That commit is the newest
run of this workflow in HEAD's history with a successful `… / Deploy to tuist`
job. Do not use the deployments API: other workflows record deployments to the
same environment. When the base cannot be resolved, the push deploys.

## Atlas deployment validation

`workflows/atlas-deployment-validation.yml` runs the standalone Compose/Helm
release checks. Documentation captures use `atlas/deploy/capture-docs.mjs` with
bounded Chrome page and process waits, rather than waiting indefinitely for
external resources. Its regression suite includes a local never-finishing image.
Retain screenshot PNGs and Chrome diagnostic logs on failures, but keep browser
profiles in the disposable validation directory, outside uploaded artifacts.

## Atlas native

`workflows/atlas-mobile.yml` builds Android, iOS and the Rust CLI through Once
using `actions/atlas-native/` (see its `AGENTS.md`). Fork jobs have no OIDC permission
and use only the local cache. Trusted builds use the `tuist/atlas-mobile` cache
when authentication succeeds, except for Android and iOS device builds, which use local caching
only so signed releases do not consume shared outputs written by PRs. Main builds publish the tested artifacts to the
private Tuist project's `nightly` preview track after distinct build, test and
language-specific lint jobs pass; pull requests never publish. The single
`atlas-mobile.yml` pipeline's automatic path filters include only `atlas-native/**`
and all jobs skip draft pull requests. Rust auth dependencies are resolved during
Once graph loading, so SwiftLint jobs install Rust as well as SwiftLint/Once.
The composite materializes locked third-party sources before graph validation;
core test jobs run both navigation and authentication suites.
Native iOS UI suites and isolated fixture apps remain local opt-in tools; CI does
not run them or gate preview publication on them. Rust, CLI and iOS unit tests
remain in the separate test jobs. Fixtures make no live account-management
requests and never enter production source globs.
Mobile artifacts are debug Android APKs, arm64 iOS simulator bundles and arm64
iOS device bundles. The protected main-branch publication job re-signs a device
bundle using the existing Tuist distribution certificate and Atlas-specific
ad-hoc profile from 1Password, then publishes its IPA alongside the APK and
simulator app in separate steps without the 1Password token. Android distribution
is re-signed with a stable key only when the protected environment configures
`ATLAS_ANDROID_KEYSTORE_REF`, its password reference, alias, and the same
`ATLAS_ANDROID_APP_LINK_SHA256` allowlist used by the server. Without a key reference,
Android nightly publication is skipped rather than distributing ephemeral debug
identities; debug CI artifacts remain. Android and simulator publication precede
iOS device signing so a profile capability update cannot block them. iOS signing
requires an Associated Domains-enabled profile and requests only the hosted app
link domain. Its provisioning guard accepts Apple's scalar wildcard authorization
as well as domain arrays, without copying a wildcard into the app signature. Credential-free Android signing, associated-domain and APNs capability,
keychain-lifecycle and launcher-packaging tests also gate publication through
`test-distribution`, which runs on macOS because the iOS capability guards require
PlistBuddy and plutil. That job also checks Live Activity extension embedding,
separate profile/device/certificate authorization and inside-out signing without
credentials. The device signing copy requires its own Live Activity ad-hoc profile;
ordinary simulator/device builds never provision one. Android builds verify locked Firebase dependencies,
explicitly merged SDK manifests, and
library R IDs against the final APK. Portable importer integrity/resource tests
run without provider credentials; device signing requires a Push-enabled profile.
PR/fork builds never receive distribution secrets. These are not
store releases; device installation requires a UDID registered in Atlas's profile. The CLI is uploaded as a
host-labeled archive that preserves its executable permission, not a Tuist preview.
The Tuist project must be connected to `tuist/tuist` for GitHub OIDC access.
The publication job installs its own Java runtime and Android build-tools, even
though it only consumes prebuilt APKs: Tuist needs `aapt2` for metadata inspection.
SDK setup from Android build jobs does not carry across to the macOS publisher.
Simulator uploads use `TUIST_PREVIEW_BUILD_VERSION` with a fresh Unix timestamp
so cached binaries do not collide with existing previews. This overrides upload
metadata without mutating or re-signing the bundle; device packaging already
stamps its delivery copy before distribution signing.

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
versions; the minimum-version job also runs the cache suite, including a real
cold remote round trip, to catch Mix/OTP artifact-layout differences. The workflow
is reused by `tuist-ex-release.yml` before publication.
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

macOS jobs in `cli.yml`, `app.yml`, `tuist-project-tests.yml` and `tuist-project-coverage-backfill.yml` use the standard
`tuist-macos-27-0` profile and install dependencies through `tuist/install`.
Custom volumes do not require the larger M4 shape. If host cache capacity is
unavailable, each attachment falls back independently to an empty job-local directory; always
run dependency installation and do not require a hit in ordinary jobs. Forks use
the same custom volumes: the runner's verified job identity authorizes attachment
without workflow credentials, and the server forbids fork publication. This is
separate from the built-in account-wide cache policy. Retained contents must be
safe for fork contributors to read. Linux and release/backport workflows have
separate toolchain and runner requirements and are not part of this migration.

`cli.yml` holds builds, lint and the Linux suite; every macOS `tuist test` run
of `tuist/tuist` lives in `tuist-project-tests.yml` (below). Lint and SwiftPM Build run on
pull requests only. The `Package.resolved`
job runs on both and checks that the lockfile's `originHash` is the SHA-256 of
the root `Package.swift`. `tuist/install` forces resolved versions, so the other
jobs never notice a stale hash, but local installs then fall back to a full
native resolution. It runs on pushes because a squash merge can produce a
`Package.swift` that no branch resolved.

Use the released `tuist/install@v1` action after tool installation and authentication.
It combines one package-relative `.build` volume with forced installation, explicit
scratch/cache paths, and symlink materialization on Tuist Runners. Other runners
use its automatic GitHub archive/copy backend. Do not add a second cache step.
The macOS native SwiftPM resolve/build commands use the same
`--cache-path "$PWD/.build/dependency-cache"`. The released CLI must include #14304
so internal manifest dumps honor that path too. Use stable per-job workspace
keys through the action's `cache-key` input (`cli-macos-workspace-${{ github.job }}`),
without Xcode-version, manifest, or lockfile hashes. The fork acceptance job uses
the stable acceptance-build key so default-branch runs can seed it. Preserve
fork guards for Tuist login, setup, and enterprise sources; installation itself
remains unconditional.
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

## Server deploy cascade volumes

The production cascade's acceptance job keeps mise's data directory, `~/.rustup`
and `~/.cargo/bin` on one `server-deploy-acceptance-tools` volume: mise records
an installed Rust as a link to `~/.cargo/bin`, so splitting them across volumes
can restore a toolchain mise believes is installed but cannot run. It installs
only `tuist` and `rust`, prunes superseded Tuist releases from the volume, and
installs dependencies through `tuist/install@v1`. `Swatinem/rust-cache` keeps the
target and registry with `cache-bin: false`; never restore an archive into a
volume path. Jobs that install part of the toolset run tasks with
`mise run --skip-tools`, otherwise mise first installs every missing root tool
(about 17 seconds on Linux). The platform chart job installs Helm and kubectl
from `infra/` for the same reason, which also keeps infra's Helm pin.

## Bazel and Mix cache volumes

Kura's `.bazelrc` configures repository downloads and disk action caching under
`~/.cache/tuist/bazel` on Linux, not its output base or remote credentials. CI
attaches that directory with the released action. Keep Tuist remote cache setup
in trusted jobs. Idle disk-cache GC has a 12 GiB target and seven-day age limit;
this is a soft cleanup target within the 20 GB volume, not a build-time quota.

`mise-install` installs Node in the same phase as npm-backed tools, not the later
locked-tool phase: cold runners have no npm until Node is installed.

Mix jobs attach their ordinary `deps` and `_build` directories together on one
volume with a readable project/job key (`ci-<project>-<job>-mix-v1`, listing
both paths), so they are restored and saved as one snapshot. Mix owns compiler and dependency invalidation; do not
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
Bootstrap `tuist_ex` and its dependencies with `mix deps.compile tuist_ex --include-children`, then explicitly run `deps.loadpaths --no-compile --no-deps-check` in the same `mix do` chain before `tuist.test --prepare-only` or `tuist.coverage.complete`. OS compilation workers do not load the SDK in the parent; discovering its task without loading those paths compiles every remaining dependency.
`tuist_ex` exchanges the job's GitHub OpenID Connect token itself, so there is no
login step. Run `db:reset -- --no-compile --no-deps-check`
in a separate process before
`mix do deps.loadpaths --no-compile --no-deps-check + tuist.test --no-download --warnings-as-errors`,
so setup cannot rebuild the downloaded artifact and migration regression tests
do not redefine modules already loaded by setup. Load paths again before final
task discovery; forwarded flags arrive too late to prevent discovery-time
compilation. Different scheduler-dependent pool sizes can invalidate the build;
do not hide runtime configuration differences by dating source files. Explicit `--no-download` test execution bypasses the
project's preparation alias too, or ecto.create starts compilation again. The
server's project-local compile function must guard the bootstrap on
`--no-compile`; list aliases pass flags only to their final action.
The build, format and seed jobs retain both `deps` and `_build` through the normal
setup action. Shards attach only `deps` and download the exact build. Always
resolve dependencies and compile the builder on cache hits. On push, instrument
only the current shards' downloaded builds for coverage; those builds are not
retained in cache volumes. The builder always archives plain outputs, keeping
its ordinary `_build` volume reusable by both main and PRs without copying.
This trades one instrumentation pass in the builder for a pass in each coverage shard.
The _build volume owns CLDR downloads; do not restore an archive inside it.
Keep mise archive caching enabled by default for jobs with additional tools;
only the measured builder/shard/coverage-completion jobs opt out. Postgres service health checks poll
every second as the `postgres` role; probing as `root` logs a FATAL on every check.
In CI, `db:reset` creates, migrates and lists migrations in one Mix process.
`bash .github/scripts/server-db.test.sh` checks argument forwarding and keeps
missing status output, pending migrations and failed Mix commands fatal.
Take shard references from the build job's outputs, not the current run attempt,
so rerunning only failed jobs reuses the original plan. Keep distinct `--scheme`
labels for ClickHouse variants so their outcomes are not treated as flaky reruns.
Pull requests plan and run the oldest-supported ClickHouse shards only when
`.github/scripts/server-clickhouse-floor.sh` finds ClickHouse migrations,
configuration, lockfiles, the workflow, added query code under `server/lib` or
`server/priv`, or the `ci:clickhouse-floor` label; every other event always runs
them, and an unreadable pull request runs them. Validate it with
`bash .github/scripts/server-clickhouse-floor.test.sh`.
Keep `TUIST_DEV_ALL_LOCALES=1` in both phases. Fork pull requests run both unsharded
variants without Tuist authentication or `id-token: write`, like the CLI and
Gradle fork fallbacks. The explicitly named unsharded fallback also runs both variants when the build-plan job fails, without changing that job's failure status. Never silently fall back to the whole suite inside an authenticated shard.

On push to main, the current ClickHouse shards also run with `--cover`,
reporting the server's coverage to `tuist/server`,
and `coverage-complete` then runs `mix tuist.coverage.complete`. The build
job plans them without `--cover`; `mix tuist.test --no-download --cover`
instruments each disposable downloaded build using native line counters.
Keep coverage
off pull requests, the merge queue, the floor shards and the unsharded
fallback, and never let it fail the run. Xcode coverage of `tuist/tuist` comes
from `tuist-project-tests.yml` (`tuist/tuist Tests`), which runs every macOS `tuist test` of the
CLI and the app (cli.yml and app.yml keep builds, lint and the Linux suite). On
a pull request the unit and app tests run selectively, acceptance as before, and
`coverage-complete` runs `tuist coverage complete` once the unit and app tests
finished, whatever their result (not on drafts or forks). On a push to main the
`cache` job warms the binary cache first, uploading the compilation-cache plugin's `cas.log`
and the CLI session logs when it fails, then the unit and app tests run in full
(`--no-selective-testing`) and `coverage-complete`
follows when both passed. The unit and app tests record per-target evidence on both,
which the CLI reads from Xcode's raw profiles (the targets don't link
TestCoverageAttribution, so there is no per-test evidence): the server carries
targets selective testing skipped only from runs that recorded evidence, main's
full runs for every selective run and a pull request's own runs for its later
pushes. Targets are carried only whole: a skipped target no run recorded
under the same hash (or whose source run fails the server's checks) has no
per-test fallback, and neither do tests skipped by identifier
(`--skip-test-targets`, `-skip-testing`), so both stay gaps (`not_linked`).
Quarantined tests are outside the figure either way. Every merge runs on its own (no queue); a new push to a
pull request cancels its run in progress, so a superseded commit is never
signalled. The default checkout is enough: every job of a run reports the same
commit, on a pull request the run's merge commit (`GITHUB_SHA`; the depth-1
checkout hides its parents, so the CLI can't resolve the head through `HEAD^2`).
`tuist-project-coverage-backfill.yml` is a dispatch-only
full run of an earlier commit on main, tested with main's `mise.toml`. The
selective runs upload coverage too; the server drops from their skips whatever a
full run of the scheme at the commit executed. The coverage settings are set once, in the
root `mise.toml`'s `[env]` (`TUIST_FEATURE_FLAG_COVERAGE`, `TUIST_COVERAGE_ENABLED`,
`TUIST_COVERAGE_PREFIX_MAPPING`), so every job that loads mise's environment and
every developer resolve the same variant and the same prefix mapping; both are
hashed into binary-cache and selective-testing keys, so never set them per step.
They stand in for `Tuist.swift`'s `coverage` option until the
backward-compatibility gate's CLI knows it. The test runs pass no
`-enableCodeCoverage`: schemes that leave their test action's coverage unset
follow the resolved option, and the acceptance-test schemes set `coverage: false`
to stay out. CLIs before tuist/tuist#14404 ignore the last two variables, so until
`mise.toml` pins one with it the runs collect no coverage and stay green
(`tuist coverage complete` leaves the commit pending). `tuist-project-tests.yml`'s single
`tuist cache` on main warms the variant those settings select: plain binaries
before that pin, the coverage variant after it. Plain environment variables
never reach the macOS test hosts (only `TEST_RUNNER_`-prefixed ones do), so
they cannot flip the CLI's own unit tests. The coverage runs pass no
`--derived-data-path`: the CLI locates Xcode's derived data itself
(`DerivedDataLocator`). If a run's export can't find it, it falls back to the
result bundle's xccov report, which never covers cached code; the server shows
that run's `coverage_tool` as `xccov`.

Keep persistent cache mounts outside `RUNNER_TEMP`: GitHub's end-of-job temp
cleanup deletes their contents before the cache-volume backend publishes them.
A warm attachment alone does not prove the snapshot retained the intended files.

`server-docker-mix-cache.yml` tests the production Mix snapshot bridge. Its manual
benchmark seeds one shared registry cache and compares the same Dockerfile and
app change with/without project-build state on fresh large runners. Require a
real cross-job snapshot restore whose `.run-id` matches the current run.
Only manually dispatched jobs get package-write permissions, and all writes go
to the isolated `tuist-mix-benchmark` package, never the deployment cache or image
tags. Count restore/export and asynchronous publication separately; a compilation
speedup alone does not establish a net win. The deployment workflows share the
stable `server-image-prod-hosted-amd64-projects-v1` volume after a measured win.
Keep fetched dependencies layer-cached, retain only the four local projects,
and make attachment/preparation/export failures fall back without failing the
image build. Historical deployment SHAs without the helper stay registry-only.
Mix owns Elixir/OTP invalidation; native outputs never enter this snapshot.

The manual Elixir benchmark also has a two-value `compilation` choice: `default` preserves the runner's compiler configuration, while opt-in `deterministic` sets `ERL_COMPILER_OPTIONS=[deterministic]` before setup and SDK bootstrap for every sample. Label summaries, artifacts, per-sample results and environment metadata with the mode and exact compiler options; never compare modes as if they were the same workload or weaken keys to hide upstream byte differences. Keep seeded-app coverage guards unchanged. Deterministic compiler output is an explicitly documented user configuration, not an SDK default or a general reproducibility guarantee.

The same workflow's manual `benchmark: elixir-remote` mode runs the actual locked server dependency graph on `tuist-linux-large`, without a Mix snapshot volume. Its Python/Elixir drivers seed the normal REAPI cache with a run-ID/attempt input namespace, then alternate disabled and remote-only clean builds. Keep the namespace identical across samples but different across reruns; do not let an already-populated production cache silently replace the cold seed. Reset pristine dependency sources and all build/local artifact state for every sample, include SDK bootstrap and server compilation, preserve the lock and interrupted results, and require actual remote writes/hits rather than accepting fail-open compilation. After generic dependency setup, restore the committed lock and use `server-elixir-cache-reconcile.exs` to fetch its exact SCM revisions without another dependency resolution; verify the lock before measuring. OIDC permission belongs only to the manually dispatched same-repository benchmark job. Record partial coverage as degraded and reject any seeded dependency that fails to restore after collecting comparisons, including key drift, bypasses and missing observations. Parse partition-prefixed compiler output. Preserve started/interrupted samples and terminate only the driver's isolated child process group on timeout/cancellation, within a total budget measured from the job's first step and below its timeout. Native download caches remain shared; configured dependency workers do not parallelize selected cache misses/bypasses. Upload raw JSON/logs, never credentials or the cache directory; endpoint metadata is origin-only. Validate the driver with `python3 .github/scripts/server-elixir-cache-benchmark.test.py` and actionlint.

The production snapshot is executable build input. It uses the existing
same-repository writer trust model, as does the registry build cache: a permitted
same-repo writer can influence production artifacts. Forks cannot publish. Do
not describe this as default-branch-only protection; deployments requiring that
boundary need server-enforced per-key restrictions or account-wide writer policy.
No workflow-side check can fence another job that can publish the same key.
If a snapshot causes compilation to fail, clear that volume in Runners → Volumes
or rotate its `-v1` key; do not retry the image build automatically.

The Docker smoke eval also runs the shipped activity-log parser with no arguments
and requires its usage message and exit code 2. Keep that assertion: app startup
alone does not check the parser's executable permissions or Swift runtime linkage.

## Restore drills

CNPG restore drills resolve production to namespace `tuist`, not `tuist-production`; staging and canary retain their prefixed namespaces. Validate the resolver with `python3 .github/scripts/cnpg-restore-drill.test.py` without credentials. Recovery clusters are isolated and must never archive into or delete the source backup path. Use a run-scoped disposable StorageClass cloned from the source data volume's provisioning settings, with `Delete` reclamation and no default-class annotation. Never change the source class or existing volumes. Teardown must target only the run's `pg-restore-drill-*` resources, use foreground cluster deletion, verify PVC/PV removal, and propagate failures rather than silently leaving copied data. Previously retained drill volumes require separate human-authorized cleanup.

## CLI Cargo cache packaging

The macOS CLI unit-test job installs the stable Rust toolchain pinned by `cas-plugin/mise.toml` before running the real Cargo/libtest fixture. Do not assume Rust is preinstalled on the runner image or silently replace the fixture with nextest.

Cargo compilation caching is implemented in Swift inside `tuist`. Do not package a separate Cargo cache executable or import an external cache engine. The existing Xcode CAS plugin and proxy remain separate Rust artifacts.

## CLI Linux builds

The Linux release ships a static musl binary built with the Swift Static Linux SDK. The PR `Linux Build` job in `cli.yml` compiles against the same SDK, installed through `mise/utilities/install_static_linux_sdk.sh` (shared with `mise/tasks/cli/bundle-linux.sh`), so it catches code that only builds against glibc. Its `.build` cache key uses the `linux-cli-musl-` prefix to stay separate from the glibc cache used by `Linux Unit Tests`, which keeps running on glibc.

## CLI release manifests

`cli-build-publish.yml` signs the final CLI archives with Packslip before publishing
any release channel. Keep signing in the checkout-free, read-only `sign-cli` job,
without the workflow-level release token; the existing publisher uploads the bundle.
Describe `tuist.zip` as universal macOS. Let Packslip infer Linux libc requirements
from the archived executables rather than declaring them. Never override libc
with `any`.
Record `inputs.ref`, not the caller's `github.sha`, as the source commit. Builds
do not currently publish provenance, so keep `attest: false` until provenance
can truthfully identify each archive's build source.

`cli-release-tests.yml` installs the CLI from the same pinned Packslip action and
runs `bash .github/scripts/cli-packslip.test.sh`. The tests use `yq`, `jq`, offline
keys, and generated ELF archives; they need neither OIDC nor release-write credentials.
They also require every release-channel caller to use the shared publisher and
keep signing unconditional across channels.

## Atlas releases

Atlas releases publish the image and standalone Helm chart with the same version, plus a Compose bundle. Managed deployment consumes the published chart with an explicit production overlay; publishing must not require cluster credentials. Deployment validation pins Helm, mikefarah yq, and jq and runs the rendering and fake-kubectl retirement checks before the image build. The offline ChatGPT configuration check verifies managed ExternalSecret sourcing, runtime `envFrom`, no explicit client-ID shadowing, and standalone/demo isolation. The push configuration check additionally verifies all APNs credential/scope references and verbatim private-PEM templating without reading real credentials. Managed deployment checks live legacy namespace retention after stuck-release recovery, because rollback can remove its retention annotation. Keep that read-only guard before upgrades that disable the legacy sandbox objects. The release-list arguments must remain compatible with the pinned Helm version; fake release-state tests also validate them against the real CLI without cluster access. After rollout and readiness, the managed release smoke test requires the public root to redirect signed-out visitors to `/login`, so a healthy but outdated or misrouted application cannot pass.

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
The job builds `inputs.ref` with the bundler and SDK setup from the
workflow's own revision, checked out into `.linux-bundler`: release lines cut
before the bundler took `TUIST_LINUX_ARCH` build only for the host, so their
aarch64 leg would package an x86_64 binary under the x86_64 name. Keep
`bundle-linux.sh` resolving `install_static_linux_sdk.sh` relative to itself.
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

## Runners acceptance

`workflows/runners-acceptance.yml` runs a job on each Tuist Runners fleet of an
environment and fails, naming the layer, when dispatch, the server's OIDC token,
Kura reachability, Kura auth, the Kura data path, Xcode cache setup or remote
cache hits break. Its scripts and fixture live in `scripts/runners-acceptance/`.
The deploy cascade's `runners-acceptance` job runs it against canary through
`gate.sh` and gates `production` on it; the hourly schedule runs it against
production's rented fleet, the BER1 rack and the Linux pool.
Canary's macOS probe runs on ber1-runner-b02, which production lends canary
(see "Lending a host to another env" in `infra/rack-nodes/AGENTS.md`); its
jobs take canary's public cache, so the rack-local cache on ber1-store-a is
covered only by the production schedule.

- A job no runner picks up stays queued for a day and `timeout-minutes` ignores
  that wait, so the in-run dispatch watchdog fails and cancels the run past the
  pickup bound. That is why the gate dispatches a separate run instead of
  calling the workflow: cancelling it must not cancel the cascade.
- Health checks are not enough: a Kura that cannot reach the server's token
  introspection answers `/up` and degrades every lookup into a slow miss. Keep
  the authenticated blob round trip and the rebuild from an empty local CAS,
  which must be fully served remotely, and fail on any cache error the builds
  or the proxy log.
- The fixture is salted per run so the rebuild can only hit what that run
  published. Keep probe job names starting with `macOS ` or `Linux `; the
  watchdog finds the jobs it bounds by name.
- Runner images export `XCODE_XCCONFIG_FILE`, pointing the compilation cache
  store at the job's cache volume and outranking a command-line
  `COMPILATION_CACHE_CAS_PATH`, so the probe unsets it and also requires the
  cas-proxy's `remote_hits` for the rebuild's store to be above zero. The
  project lives in `project/`, not `fixture/`: the root `.gitignore` ignores
  `Fixture`, which matches case-insensitively on macOS.
- On canary only, the macOS probe also round-trips cache volumes, and a failure
  blocks production like any other layer. `scripts/runners-acceptance/volume.sh`
  attaches four volumes after the Xcode build, since GitHub can report which job
  a runner runs later than the host's 25-second authorization budget: custom
  volumes `runners-acceptance-probe` (emptied and reseeded with the run id each
  run) and `runners-acceptance-static` (written once, then never changed, which
  covers an unchanged volume losing its saved copy), and the managed Xcode and
  module cache volumes through the in-repo `actions/xcode-cache` and
  `actions/module-cache`, each with a run-id marker at its root. The job's last
  step writes a 256 MB payload into the probe volume, so the host's
  incomplete-image check and the guest's detach flush handle a large final
  write. `volume-wait` then waits on a GitHub-hosted runner for the host to
  publish, and `macos-volume` attaches them all and requires `cache-hit=true`,
  a real APFS mount, the run id or a later one (overlapping probe runs share
  the volumes), the payload's checksum and exactly the seeded entries. An
  older run's id is a failure unless that run's seed job overlapped this one's
  (each widened by the 120 s publish allowance): both cloned the same saved
  copy and the host turns down whichever saves second, so the volume is
  `Cache volumes inconclusive`. Verify reads both seed jobs' times from the
  Actions API, which is why `macos-volume` has `actions: read`.
  Canary has one rack host, so verify lands where seed published; production's
  multi-host fleets would make it depend on convergence.
- The script attaches through the in-repo action sources rather than the
  released actions because it reads the client's output: an unavailable volume
  falls back to a job-local directory and the job still succeeds, so any
  fallback fails as `Cache volumes`, except one refused because GitHub had not
  yet reported the runner's job (the client's "GitHub had not yet reported which
  job this runner is running", the server's 425 `execution_pending`). That is a
  webhook delay, not a regression: the volume is skipped with a
  `Cache volumes inconclusive` warning, the seed job hands its skipped volumes
  to verify, and `gate.sh` re-raises the warning without failing. The round trip
  is not retried: the regressions it guards against were deterministic or
  intermittent save losses, which a retry would hide or merely repeat.
  The pattern must match `errExecutionPending` in
  `infra/linux-runner-image/cmd/tuist-cache-volume/main.go`.
  `macos-cache-volumes-smoke.yml` covers the released `tuist/cache-volume`.
- To prove a broken endpoint fails fast, dispatch with `cache_endpoint` set to a
  wrong URL; it skips the expected-host check and overrides what dispatch hands
  each job.

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
