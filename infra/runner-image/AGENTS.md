# Runner Image

Tart VM image hosted on the **customer-runner Mac mini fleet**
(`tuist.dev/fleet=<runnersFleetName>`). One image, one Tart VM
per Pod, one ephemeral GitHub Actions runner per VM, one job per
runner.

## What's in the image

The runtime user is `runner` with home `/Users/runner`, matching
GitHub-hosted macOS runner images. On-disk artifacts that bake
absolute paths (SwiftPM `.build/checkouts/`, Xcode DerivedData,
`actions/cache` payloads) are interchangeable between hosted and
self-hosted runs without per-environment cache keys.

The Cirrus base image's pre-existing `admin` user is kept around
as the Packer SSH provisioning identity but is not used at
runtime — no service, sudo entry, or auto-login targets it.

Because the base images provision as `admin` and jobs run as
`runner`, anything the base installs under `admin` has to be
handed over explicitly. Three things are:

- `/opt/homebrew`. The prefix shipped owned by `admin`, so `brew
  install` from a workflow step failed its writability audit
  while `brew` itself resolved fine on `PATH`. GitHub-hosted
  images build and run under one account, so the job user owns
  the prefix — this image chowns it to `runner` to match.
- `~/.zprofile`. The cirruslabs base writes it for `admin` and
  symlinks `/Users/runner` at `/Users/admin`; this image replaces
  that symlink with a real `runner` account whose home comes from
  macOS's user template and has no `.zprofile`, so the file is
  copied over. Without it the login shell the LaunchAgent (and
  every step shell under it) runs resolves no brew shellenv, no
  rbenv, no node.
- The Metal Toolchain. On Xcode 26.1 a toolchain downloaded by
  `admin` is not usable by `runner`, so the image downloads it again
  as `runner`, with the same explicit `-buildVersion` the base uses
  (see `infra/macos-xcode-image/AGENTS.md`). Base images built before
  the toolchain was added to them have none, and this download is
  what installs it.

When adding tooling to the base, check ownership and login-shell
reachability from `runner`, not just presence under `admin`.

A related class of gap is anything GitHub-hosted images pre-seed
that ours do not. When adding parity features, compare against
`actions/runner-images` `images/macos/scripts/build/`, and pair
each one with a check that asserts the behaviour rather than the
ingredient — every gap so far was found by a release failing, not
by the image build.

TCC is one of those gaps. Two standing approvals live in `runner`'s own
`~/Library/Application Support/com.apple.TCC/TCC.db`, the same rows
GitHub-hosted images ship:

- **Scripting Finder.** `create-dmg`, or anything driving Finder through
  `osascript`, needs `kTCCServiceAppleEvents` approved, or the first send
  waits on a consent prompt nobody can answer and fails as `AppleEvent
  timed out (-1712)`.
- **The iOS Simulator's microphone.** A simulator app that records audio
  (`AVAudioSession` in `.playAndRecord`, `AVAudioEngine`'s input node, a
  video-call SDK) reaches the host microphone through coreaudiod, and TCC
  charges it to `com.apple.CoreSimulator.SimulatorTrampoline`. Without a
  row the app's audio call never returns, its main thread stalls, and
  XCUITest fails with `Failed to get matching snapshots: Timed out while
  evaluating UI query` or `Unable to monitor event loop`. The iOS-level
  permission inside the simulator (`simctl privacy`, the in-app alert) is
  separate and stays the job's responsibility. Simulators have no camera,
  so `AVCaptureDevice.default(for: .video)` is nil there on any host.

`tcc-approvals.sh` writes them at image build. The Packer template reboots
the build VM so `runner` auto-logs in, waits for the TCC.db that login
makes runner's tccd create, seeds the rows into it as `runner`, then
reboots once more and fails the build unless every row is still there.
At boot, `dispatch-poll.sh` (`check_tcc_approvals`) only reads them and
logs `tcc-approvals: all approvals present` or `WARNING tcc-approvals:
missing …`; for VMs whose log tail reaches Loki, search the
`tuist-macos-tart-kubelet` `runner log` lines for it.

What decides whether a row matches:

- **Database.** Only the session user's database is consulted, for both
  services. A row in the system database is ignored: coreaudiod asks the
  system tccd, which forwards to the user tccd, and the user tccd decides.
  PPPC configuration profiles cannot grant Microphone or Camera (deny
  only), so MDM is not a route.
- **Client.** TCC charges an AppleEvent to the responsible process, not to
  `osascript`. For GitHub jobs that is
  `/Users/runner/actions-runner/bin/Runner.Listener`. The Buildkite and
  GitLab agents are started directly by `dispatch-poll.sh`, so theirs is
  expected to be its `/bin/bash`. The microphone row is a bundle-ID client
  (`client_type` 0). `log stream --predicate 'subsystem == "com.apple.TCC"'`
  names the charged process (`Prompting for access to indirect object
  Finder by …`, `AttributionChain: responsible=…`).
- **Target.** The Finder rows' `indirect_object_code_identity` must hold
  Finder's code requirement. A row with it NULL is ignored.

Why the rows are written at build and not at boot: the database only
exists once `runner` has logged in, and before the template rebooted into
`runner`'s session nothing in the build did, so the image shipped with no
user TCC.db at all. tccd then created one about 8 s after every VM boot,
which looked like tccd recreating a database seeded at build. It was not:
a database tccd created in the build session keeps its inode and birth
time through `tart push`, the clone, and boot on a cluster node, and tccd
honours its rows. Writing at boot instead raced tccd, which is still
writing the database right after login (`database is locked` without a
busy timeout, then `-1712` or `-1743`), and a microphone row written after
a prompt is already pending does not unblock coreaudiod.

An earlier attempt (the build-account rename in
[#13597](https://github.com/tuist/tuist/pull/13597)) wrote rows into `admin`'s database during
the build and then moved `admin`'s home to `/Users/runner`. That file was
gone at boot. The system tccd keeps a registry of user databases in
`/Library/Application Support/com.apple.TCC/REG.db` (table `registry`:
`abs_path`, `first_seen`, `last_seen`, `trusted`), and the user tccd calls
`TCCCheckIfDatabaseIsRegistered` when it starts. That database had only
ever been registered at `/Users/admin`. This is the likely reason, not a
confirmed one. Seed the database tccd created for `runner` at
`/Users/runner`, and do not move or copy a TCC.db into place.

macOS 27 moves the user database to
`/private/var/containers/Data/ProtectedSystem/<id>/Data/Library/Application Support/com.apple.TCC/TCC.db`.
`tcc-approvals.sh` only knows the Tahoe path, and its `wait` step fails the
image build when the database does not appear there, so a macOS 27 base
breaks the build instead of shipping without approvals. The build-time
approach should carry over, because the container lives on the image's
disk, but resolve the path from runner's tccd (`lsof -p <pid>`) and verify
it on a macOS 27 guest first.

Some jobs on images that wrote the Finder approval at boot failed with an
immediate `-1743` although boot logged approval. `dispatch-poll.sh`
streams TCC at Info level as newline-delimited JSON, so multiline request
bodies retain their service and target fields. At exit it appends
`dispatch-poll: tcc:` lines after the job output: Finder grant rows,
database inode/birth time, tccd start times, and AppleEvents request summaries.
Requests are keyed by daemon PID and message ID; no-ID attribution/decision
events use the most recent request on the same daemon thread. This is
best-effort adjacency, not a proven cause or perfect correlation after dropped
events. Other explicit services are excluded. Parse only the latest MiB;
retain the last observed `authValue=0` denial and nine recent requests, capped
below the host's 200-line/64-KiB tail. An `authValue=1` undetermined state is a
fallback only when no explicit denial is captured. Older requests can fall
outside this window.

Stream shutdown has a one-second kill grace; report work has a five-second
deadline and one-second grace, so diagnostics do not indefinitely delay normal
VM teardown. Only still-running shell-owned stream jobs are signalled, and the
saved PID is cleared. Capture failure must not change the job's exit code.
The raw stream is temporary inside the guest and grows for the job lifetime;
only the bounded report is exported. No grants, probes, or daemon reloads are
introduced. Remove the capture when the failure is understood.

Run `bash infra/runner-image/tcc-report_test.sh` from the checkout. It also
covers `tcc-approvals.sh`. Tests use synthetic JSON and temporary
SQLite/processes, never host privacy APIs. The existing release workflow
runs them on PRs and before releases with a separate read-only test job; PR events never plan, build, publish, or deploy images.

The sanity checks at the end of the Packer template run as `sudo
-u runner -H`. macOS sudoers keeps `HOME`, so dropping `-H`
leaves them pointed at `/Users/admin` and they assert against the
provisioning account's environment instead of the runtime one —
which is how a reachability check stayed green through months of
broken `brew install`s, and how the `brew install hello` check
added to catch that failed on `admin`'s unwritable cache instead.

- `/Users/runner/actions-runner/` — GitHub Actions runner binary
  (no registration; we register at runtime via JIT config minted
  by `Tuist.Runners.Reconciler` / `Tuist.Runners.Dispatch`).
- `/opt/tuist/buildkite-agent` — Buildkite agent binary, for jobs
  dispatched from a customer's Buildkite cluster. Both agents live in
  the one image because which one runs is decided per job at dispatch,
  so a warm Pod has to be able to serve either; forking the image would
  split the warm pool to save one binary.
- Packer uses the shared SPKI policy in `../certificate-trust/` to remove the
  compromised eMudhra keys from curl's independent `/etc/ssl/cert.pem`, verifies
  curl/Homebrew bundles, and installs system-keychain deny settings from Apple's
  root certificates. A real AAA intermediate is tested before/after with offline
  native verification and a known ISRG root positive; already-denied baselines
  are recorded without claiming differential success. Controls are actual Packer
  and release-plan inputs. Qualify fresh-VM Apple and effective job-user behavior
  before release; source/syntax checks or a settings write are not proof. Preserve warm pools and cache masters
  during rollout; see `../certificate-trust/README.md`. Dispatch and the Buildkite
  environment hook force Node/Python onto the patched PEM store; the GitLab
  executor explicitly forwards those settings to its sanitized job environment.
- The Go shell agent embeds the twelve-key deny for discovery HTTP and WSS,
  after ordinary native verification, retaining direct/no-proxy dialers and
  TLS defaults. Keep its shared main/policy files, trust tests and fixtures byte-identical to
  the Linux copy. Refuse HTTPS/secure-discovery downgrades, including raw-origin
  opt-out, and never print credential-bearing URLs or server response bodies.
  See `../certificate-trust/RUNNER-CLIENTS.md`: host tests do not qualify a
  Packer image or already-running process. Preserve active jobs/warm floors.
- `/opt/tuist/buildkite-hooks/` — global agent hooks (`--hooks-path`),
  so they run for every job regardless of what the customer's
  repository defines. `environment` re-exports the cache settings the
  server sent (the agent sanitizes the job environment, so an export
  from `dispatch-poll.sh` does not survive into the job) and stamps the
  job's start; `pre-exit` posts the job's log and its window back to the
  server, authenticating with the job-scoped report token dispatch
  minted rather than the Pod's SA token. The same two hooks ship in the
  Linux image (`infra/linux-runner-image/buildkite-hooks/`) and share the
  same job settings protocol. The environment hooks differ in their platform's
  patched CA bundle path. They take their job paths from `TUIST_RUNNER_JOB_ENV`
  and `TUIST_RUNNER_STATE_DIR`. The log comes from `BUILDKITE_JOB_LOG_TMPFILE`, which the
  agent writes because it is started with `--enable-job-log-tmpfile` and
  deletes when the job ends — hence a `pre-exit` hook rather than
  anything later. `pre-exit` also writes the job's outcome as it sees it
  (`succeeded`, `failed` or `canceled`) to `job-result` in its state
  directory, ahead of the credential check, for the cache-volume save gate
  below. Only the macOS teardown reads it, and only together with the agent's
  exit status (see below). `canceled` comes from `BUILDKITE_JOB_CANCELLED`,
  which the executor sets for the hooks that run after a cancel.
- `/Users/runner/work/<owner>/<repo>` — workspace path the JIT
  config sets via `work_folder: "/Users/runner/work"`; matches
  GitHub-hosted's `GITHUB_WORKSPACE`.
- `/opt/tuist/inject-env.sh` — root-owned helper; reads
  tart-kubelet's env mount (`/Volumes/My Shared Files/env/tuist.env`)
  into `/etc/tuist.env`.
- `/opt/tuist/dispatch-poll.sh` — polls
  `TUIST_RUNNER_DISPATCH_URL?pod_uid=…&token=…`. Each request carries the
  guest's `sw_vers -productVersion` as `os_version`, which the server
  puts in a macOS runner's name (`tuist-macos-26.6-xcode-27.0-6vcpu-14gb-<hex>`,
  see `runner_name_prefix/4` in `server/lib/tuist/runners.ex`). While 204 it
  sleeps; on 200 it runs the agent the response selects: `./run.sh
  --jitconfig $JIT` for a GitHub job, or `buildkite-agent start` with
  `BUILDKITE_AGENT_ACQUIRE_JOB` set for a Buildkite one. The Buildkite
  branch skips the idle watchdog entirely — an acquisition token names
  one job UUID, so there is no window in which a registered agent waits
  to be handed work, which is the whole hazard that watchdog bounds.
  For a GitHub job it writes the response's `setup_info` to the
  runner's `.setup_info`, which the runner prints in the job's "Set up
  job" step as a "Tuist Runner" group linking to the job's dashboard
  page (`/<account>/runners/by-runner/<runner name>`, resolved
  server-side because GitHub picks the job after the file is read).
  Captures
  the rc and `sudo shutdown -h now`s the VM via an `EXIT` trap so
  `tart run` returns and tart-kubelet flips the Pod to
  Succeeded — the watcher's GC + warm-pool refill are gated on
  that transition.
  **Caches.** The Xcode compilation cache and the Tuist module cache each live
  on a managed custom volume, `tuist-xcode` at `MANAGED_XCODE_CACHE` and
  `tuist-module` at `MANAGED_MODULE_CACHE`; the runner image has no other cache
  path. After dispatch and before the runner starts, `stage_runner_caches`
  writes `mode` (`opt-in`) and, through `stage_managed_cache_volumes`, each
  cache's `<cache>.volume` (key and path), its environment in
  `/Users/runner/.tuist-runner-caches/{module,xcode}.env`
  (`TUIST_XDG_CACHE_HOME` and `TUIST_CACHE_MAX_BYTES`; `XCODE_XCCONFIG_FILE`,
  `TUIST_COMPILATION_CACHE_CAS_PATH` and `TUIST_CAS_DRAINED_STORE`), and the
  compilation cache's own xcconfig bounding its store to
  `MANAGED_XCODE_CACHE_LIMIT_BYTES`. Nothing reaches the runner's environment
  until a job asks: the `tuist/module-cache` and `tuist/xcode-cache` actions,
  Buildkite plugins and GitLab snippets (`ci/runner-caches/`) run
  `/usr/local/bin/tuist-runner-cache activate <cache> [--size NGB]`, which
  attaches the volume with `tuist-cache-volume`, passing the size, once per job
  (`<cache>.attached`), prints the
  environment for the integration to export, chains a workflow-set
  `XCODE_XCCONFIG_FILE` last (a relative one resolved against the step's
  working directory), and leaves `<cache>.used`. It exits 3 without exporting
  anything when the attach fails or the cache was not staged. An absent `mode`
  means a runner that never staged caches, including one whose directory could
  not be created; the helper then exits 0 and the job runs without them. Keep
  the helper's env contract in step with these files, and run
  `runner-caches_test.sh`. After the attach the helper reads the volume's
  capacity (`df` on the path, which links into the mounted image) and rewrites
  `TUIST_CACHE_MAX_BYTES` in `module.env` or `COMPILATION_CACHE_LIMIT_SIZE` in
  the xcconfig. The module cache's limit is the capacity less max(2 GB, 20%), at
  most half of it: 16 GB at the default 20 GB. The compilation cache's is half
  that space, 12 GB at the default 30 GB, because `COMPILATION_CACHE_LIMIT_SIZE`
  bounds one generation and the store keeps two (the primary and its upstream).
  A path left as a local directory (the
  volume was unavailable) keeps the staged limits of a default-sized volume. The
  teardown prune bounds the store at the limit the xcconfig gave the compiler
  (`managed_xcode_cache_limit`), so both follow the capacity the job set with
  `size` (the server's defaults: 30 GB `tuist-xcode`, 20 GB `tuist-module`).
  Keep the limits under the 99% fill at which a volume is no longer saved. The
  runner image reads nothing from the host's `cache` share and calls none of
  the server's volume HEAD routes, so it works with hosts that still offer that
  share and with hosts that do not.
  Only a job that **succeeded** saves its cache volumes. The gate is
  `JOB_PASSED` (zero exit AND a job result of `succeeded`), not the runner's
  exit status. `run.sh` folds every Listener code except a restart into 0, and
  the GitLab executor exits 0 for job outcomes by design. A job whose result is
  `failed` still detaches its volumes (`cache_volumes_detached`): the server
  discards a failed job's volumes, and the detach reports how full each one
  got, so a copy that ran out of space clears its saved snapshot.
  GitHub's verdict is the Listener's `_diag/Runner_*.log` line `finish job
  request for job <id> with result: <Result>`, matched only at a `JobDispatcher`
  trace header, because a later line echoes the job's display name. The Listener
  writes that line on both its normal and its cancel/abandon path, with the value
  it reports to GitHub.
  GitLab's verdict is `/var/log/tuist-runner/job-result`, written by
  `tuist-gitlab-runner --result-file`. Buildkite's is that file as the
  `pre-exit` hook wrote it, turned into `failed` when the agent, started with
  `--reflect-exit-status`, exits non-zero (`buildkite_job_result`). The hook
  alone misses failures the executor settles after it: an automatic artifact
  upload, or a repository or plugin `pre-exit` hook. The status alone misses a
  cancel. The script still exits 0 for any job the hook saw, because the
  runners-controller reads a non-zero runner exit as a runner death. A
  failed, cancelled or missing verdict withholds the teardown prune and
  `tuist-cache-volume --detach-all`. The drain still runs for every job that
  used the compilation cache. Three sources that look usable are not:
  - the Worker's `Job result after all job steps finish` line is never written
    when a job fails to initialize or its Worker crashes;
  - `ACTIONS_RUNNER_RETURN_JOB_RESULT_FOR_HOSTED` returns 100 + the result, but
    `run.sh` still folds that into 0, and the Listener reports `Succeeded` when
    its dispatch throws;
  - `ACTIONS_RUNNER_HOOK_JOB_COMPLETED` runs as a job step before the result is
    settled, and no status variable reaches it.
  Teardown order is load-bearing. For a job that left `xcode.used`, teardown
  points `CAS_STORE_ROOT` at the compilation cache and first **waits for its
  publications to reach the remote** (`drain_cas_publications`), then prunes it
  (`prune_cas_stores teardown`, successful jobs only). Then
  `stop_tuist_launch_agents` boots out every `tuist.*` launch agent the CLI
  installed during the job (the image's own agents are `dev.tuist.*`) and waits
  up to 10 s for each process to exit, since `launchctl bootout` returns first.
  These agents outlive the runner's process cleanup and restart on an
  unsuccessful exit, so they are booted out, not killed. The proxy holds the
  compilation-cache store open, and a Tuist installed onto a custom volume (for
  example mise's install directory) runs from it; either keeps a volume busy,
  so its clean detach fails with EBUSY. Only then do the checkout export and
  `tuist-cache-volume --detach-all` run.
  The server also delivers a `cache_signing_grant` in the dispatch 200, exported
  as `TUIST_CACHE_SIGNING_GRANT` so the EE CLI signs artifacts with the account
  scope instead of the machine MAC, which is what lets a saved volume's binaries
  validate across the account's VMs.
  `cas_proxy_client` resolves an explicit proxy override, the installed agent's
  configured override or CLI bundle, PATH, then the image fallback. For stable
  `/bin/sh` agents it reads the JSON launch target from ProgramArguments[2];
  for explicit custom/source-built agents it reads the CLI from
  ProgramArguments[4]. Legacy agents still name the CLI in Program. Run
  `bash infra/runner-image/tests/cas-proxy-client-test.sh` on macOS to cover
  all discovery modes without starting the dispatch loop.
  The store is bounded by `prune_cas_stores` and by nothing else.
  `COMPILATION_CACHE_LIMIT_SIZE` bounds a GENERATION, not the directory: llcas
  rotates (new primary, old one demoted) when the chain is over the limit and
  its last handle closes, and only `llcas_cas_prune_ondisk_data` deletes what
  falls off, which no part of a build ever calls. The prune runs through
  `tuist-cas-proxy --prune`, not this shell, because the per-machine proxy holds
  a handle per path for its lifetime and only the holder can rotate a store. A
  store no proxy holds is pruned on its generation dirs under the store's
  `lock` without opening it, so it works on a full volume and on stores the
  compilers or another Xcode wrote. Every lane is swept (`plugin`, and
  `builtin`/`generic` from builds without our plugin), discovered by their
  `v1.N` generation dirs, and the compilation cache's limit is SPLIT between
  them: it budgets the CAS as a whole while llcas only takes a per-generation
  bound per store, so handing each the full figure would let a multi-lane job
  occupy a multiple of the volume. The split is by use (`cas_store_budgets` over
  `split_by_use`): a store whose need, twice its allocated size and at least
  256 MiB, is under an even share gets that need, and the stores that need more
  split the rest. Teardown is the only place that can count the lanes, since
  `COMPILATION_CACHE_LIMIT_SIZE` is staged before any of them exist.
  Xcode ranks `XCODE_XCCONFIG_FILE` above `-xcconfig` and both above
  command-line build settings (`xcodebuild -showBuildSettings` and the
  compiler's `-cas-path` on Xcode 26.0.1 and 27.0; read the target's section,
  not the "Build settings from command line" header that echoes the
  arguments). So while the runner's xcconfig is in effect, a
  `COMPILATION_CACHE_CAS_PATH=...` argument does NOT move the store, including
  the one `tuist cache` passes. The staged environment still exports
  `TUIST_COMPILATION_CACHE_CAS_PATH`: it is what `tuist cache` names, which
  only takes effect for a step that replaces `XCODE_XCCONFIG_FILE` with a file
  that does not set the path, and it is where scripts read the store's
  location. It exports `TUIST_CAS_DRAINED_STORE` too: on CI the CAS plugin
  otherwise makes every cache put wait for its upload, because off a runner the
  store goes away with the job, and `drain_cas_publications` does that wait at
  teardown for spools under this directory, after the job has reported its
  result. The plugin compares the store the compiler actually opened, so it
  uploads in the background only when that store is inside this path; a job
  whose own xcconfig moves `COMPILATION_CACHE_CAS_PATH` elsewhere, or that
  drops `XCODE_XCCONFIG_FILE` and names another path, keeps waiting.
  The drain exists because the store's objects are uploaded to the remote cache
  asynchronously, through the CAS plugin's spool, while the associations naming
  them are written into the store immediately. Saving the volume ahead of those
  uploads hands every later job keys naming objects nothing can produce,
  permanently (the compiler's CAS ABI has no delete, and re-putting a key with
  a different value is refused, so such a key fails until the store generation
  rolls). The gate asks the running proxy (`tuist-cas-proxy --drain`, exit 0
  drained / 3 owed / anything else "could not ask") and falls back to watching
  `<cas dir>/tuist-spool` itself when no client can be found; a record is
  deleted only by a publication that SUCCEEDED, so an empty spool is the proof
  either way. It runs on a failed job too, whose uploads the next job still
  needs, and is a no-op for a job that never published, which includes every
  plain `xcodebuild` using Xcode's builtin lane. Not draining within
  `CAS_DRAIN_TIMEOUT` (120 s) withholds the job's volumes. It cannot be
  complete, so it complements, and does not replace, the plugin's read-side
  check on a local hit.
  `XCODE_XCCONFIG_FILE` is the mechanism because the common case is a plain
  `xcodebuild build` against a project Tuist never generated and never wraps,
  which the generate-time project mapper and the `tuist xcodebuild` wrapper both
  miss. It is the one layer every xcodebuild invocation honors
  (`COMPILATION_CACHE_*` exported as plain env vars does nothing). The xcconfig
  deliberately does **not** set `COMPILATION_CACHE_ENABLE_CACHING`: enabling the
  cache stays the project's opt-in, and this only says *where* an
  already-caching build keeps its store. `XCODE_XCCONFIG_FILE` is an OVERRIDES
  layer (swift-build's `environmentConfigPath`), so it FORCES the CAS path over
  project and target settings, `-xcconfig` and the command line alike. The
  escape hatches are a workflow's own xcconfig, which `tuist-runner-cache`
  `#include`s LAST, so anything it sets explicitly (the CAS path included)
  still wins, and running xcodebuild without `XCODE_XCCONFIG_FILE`, as
  `.github/scripts/runners-acceptance/xcode-cache.sh` does.
- `/opt/tuist/metrics-poll.sh` — the machine-metrics sampler.
  `dispatch-poll.sh` forks it into the background right before it
  starts `./run.sh`, so it samples whole-VM CPU/memory/network/disk
  (`top`/`vm_stat`/`netstat`/`df`) for the job's duration and POSTs to
  `…/pods/<pod>/metrics` with the same SA token, dying with the VM when
  the job ends. Best-effort; never blocks the job.
- `/opt/tuist/tuist-cas-proxy` — the last-resort compilation-cache (CAS) prune
  client, built from `cas-plugin/` alongside `runner-shell-agent` by
  `.github/actions/build-runner-image-binaries`. Every `provisioner "file"` in
  `runner.pkr.hcl` is a MANDATORY input and the template has two callers
  (`runner-image.yml` and `runner-image-release.yml`), so a binary built in
  only one fails the other with `Bad source`. Add new
  provisioned binaries to that action, not to a workflow. `cas_proxy_client` prefers the binary beside the tuist
  that `tuist setup cache` installed (it matches the proxy actually running,
  which is what a drain must talk to) and falls back to this one. It exists
  because a plain `xcodebuild` workflow never runs Tuist, so it installs no
  cas-proxy at all — and those jobs still write the compilers' `builtin` CAS
  lane into the volume, so without a binary here nothing on the machine could
  ever bound it. It is only ever invoked as `--prune`/`--drain`; the image runs
  no CAS daemon of its own.
- `/opt/tuist/runner-shell-agent` — interactive shell bridge.
  `dev.tuist.runner-shell-agent` starts `runner-shell-agent-supervisor.sh`
  at boot and waits until `/etc/tuist.env` and `/etc/tuist-sa-token` are
  materialized, then blocks on `/tmp/tuist-runner-shell-claimed` until
  `dispatch-poll.sh` receives a JIT claim. It polls the server for authorized
  shell sessions and forwards a PTY in the runner VM over the server-owned
  WebSocket tunnel. The binary is built from the Go source in
  `cmd/runner-shell-agent/`, so dashboard terminal access and
  `tuist runner ssh` attach to the same ephemeral job environment without a
  Python runtime dependency.
- `/opt/tuist/runner-shell-agent-supervisor.sh` — restarts the trusted
  shell bridge while the single-shot runner VM is alive. It runs as root
  from a LaunchDaemon so terminal access does not depend on an unlocked
  Aqua session, then drops PTY child shells to the `runner` user.
  `/tmp/tuist-runner-shell-agent.lock` keeps it a singleton, and both uids
  share that one path, so probe the holder with `ps -p` and never with
  `kill -0`: from `runner`, `kill -0` fails with EPERM against the live
  root-owned daemon exactly as it fails with ESRCH against a dead pid.
  An unreadable pid file or a refused `rm` means the lock is held, not
  stale; clearing it there starts a second bridge against the same
  dispatch URL and claim marker. `dispatch-poll.sh`'s
  `shell_agent_lock_active` implements the same protocol and must stay in
  step with it.
- `/Library/LaunchDaemons/dev.tuist.runner-shell-agent.plist` — the
  boot-time LaunchDaemon for the shell supervisor. `dispatch-poll.sh`
  still has a singleton-lock guarded fallback start path for older or
  partially-built images.
- `/Users/runner/Library/LaunchAgents/dev.tuist.runner.plist` —
  the LaunchAgent that auto-runs `inject-env.sh` then
  `dispatch-poll.sh` once runner's user session starts at boot.
  Wraps the entrypoint in `zsh -lc` so `~/.zprofile` is sourced
  (Homebrew shellenv, rbenv init, LANG=en_US.UTF-8, PATH
  additions for the cirruslabs base's pre-installed tools), so
  step shells see the same environment an interactive SSH
  session on the same VM would.
  `dispatch-poll.sh` also exports `ImageOS` (e.g. `macos26`, from
  `sw_vers`) before starting the runner, as GitHub-hosted runners
  do; setup actions such as `erlef/setup-beam` read it to pick a
  prebuilt binary.
- `/etc/kcpassword` + `autoLoginUser=runner` — macOS auto-login
  config so the desktop session exists at boot and loginwindow
  loads the LaunchAgent. Without this the VM boots to a login
  screen and the agent never starts.
- `SetupAssistant` and `SetupAssistant.managed` defaults — skip
  first-run panes such as Apple Account, Privacy, Siri, Screen Time,
  and automatic software update so VNC opens on the runner desktop
  instead of Setup Assistant.
- `pmset`, `com.apple.screensaver`, and `com.apple.autologout`
  defaults — keep the ephemeral runner desktop from sleeping, locking,
  or auto-logging-out during interactive VNC sessions.
- `/etc/sudoers.d/runner-nopasswd` — passwordless sudo for the
  agent's privileged ops (installing /etc/tuist.env, halting the
  VM at job exit). Single-tenant ephemeral VM — the entire OS is
  the customer's job environment.

## Build

```bash
cd infra/runner-image
mkdir -p build
go build -trimpath -ldflags="-s -w" -o build/runner-shell-agent ./cmd/runner-shell-agent
packer init runner.pkr.hcl
packer build runner.pkr.hcl
```

CI:
- **Releases.** `.github/workflows/runner-image-release.yml` runs on
  pushes to `main` under `infra/runner-image/**` and on
  `workflow_dispatch`, in its own concurrency lane, off the server
  deploy path:
  1. `plan` (`.github/scripts/runner-image-release-plan.sh`) rebuilds a
     profile when the image's sources changed in a releasable commit,
     when the previous release did not carry it, or when its
     `macos-tahoe-xcode` base resolves to a different digest than the
     one in the previous release's `build-manifest.json`. Every other
     profile is carried over. A base-only change releases a patch
     version.
  2. `build` fans the rebuilt profiles across the `vm-image-builder`
     hosts. Each clones its base by digest and pushes
     `:macos-<dashes>-<semver>` and `:macos-<dashes>`.
  3. `carry` re-tags `:macos-<dashes>-<previous>` as
     `:macos-<dashes>-<semver>`, a manifest copy with no layer upload.
  4. `release` checks every profile tag is published, then creates the
     `runner-image@<semver>` tag and GitHub Release with
     `build-manifest.json` attached. The chart's
     `runnersFleet.runnerImageSemver` resolves to that tag at deploy
     time, and `server-deployment.yml` resolves each profile that
     release lists in `profiles.json` to the digest its tag serves
     (`runnersFleet.runnerImageDigests`). Pools name the digest, so a
     carried profile's pools, warm Pods and host goldens stay as they
     were. A profile tag that cannot be resolved fails the deploy.
  5. `announce` writes each profile's standalone and stacked digest into
     the `tuist-upcoming-runner-images` ConfigMap of canary and
     production, so their macOS hosts pull the images their pools move
     to, and waits until they hold them (see "stages" in
     `infra/tart-kubelet/AGENTS.md`). Every deploy holds a pool on its
     current image until then, for up to an hour; dispatch the release
     with `skip_staging` to move the pools at once. A failure in
     `announce` does not hold the deploy.
  6. `deploy` dispatches `server-production-deployment.yml`, which
     rolls the fleet through canary.

  `macos-xcode-image.yml` dispatches the workflow after publishing a
  base an active profile builds on, so a rebuilt base or a moved beta
  channel reaches the fleet without a repo change.
- **Ad-hoc rebuilds.** `.github/workflows/runner-image.yml`
  (`workflow_dispatch`) builds + pushes a SHA-tagged image for one
  profile without cutting a release.

Both flows run on the bare-metal `vm-image-builder` Mac mini
fleet that also builds xcresult-processor. Tart needs a live GUI
session for Virtualization.framework, so this can't run on
hosted runners. Builder fleet operator runbook:
[`../vm-image-builder.md`](../vm-image-builder.md) — cluster-
managed via the same CAPI provider as the macOS Node fleets;
scale via `buildersFleet.replicas` / `kubectl scale`.

Both flows publish through the shared
[`tart-push`](../../.github/actions/tart-push/action.yml)
action. It bounds registry concurrency, chunks large layers, randomizes
retry timing across builders, and captures registry-path diagnostics.
Keep manual and production image publication on that shared action.

## Layer 1 dependency

This is **Layer 2** on top of
`ghcr.io/tuist/macos-tahoe-xcode:<xcode-version-dashes>` (built by
`infra/macos-xcode-image`). Xcode + dev tools + WWDR certs all
live in Layer 1; this layer just adds the GitHub Actions runner
agent + dispatch loop + runner user / launchd wiring on top. A
Layer 2 rebuild on every runner-image commit costs ~2 min instead
of the ~30 min an all-in-one rebuild used to cost.

### Stacked images

Every release also publishes each profile as a Tart stacked image,
`:macos-<dashes>-<semver>-stacked` (and the rolling
`:macos-<dashes>-stacked`): Layer 1's disk stays a read-only base, and
the runner layer is an ASIF overlay. Clone and run need macOS 27 and
Tart 2.36 or newer, so only rack hosts run it. Older hosts can pull one
but not boot it.

- **Release.** The plan builds a profile's stacked image whenever it
  rebuilds the standalone one, and when the previous release published
  none for it (its `build-manifest.json` entry lacks `stacked: true`).
  Otherwise `carry` re-tags it like the standalone tag. The
  `build-stacked` job runs on the macOS 27 builder (`macos-27` label),
  and the release gate requires both tags of every profile.
- **Where it runs.** `server-deployment.yml` resolves each published
  stacked tag's digest into `runnersFleet.runnerImageStackedDigests`.
  Rack pools run it when `rackFleet.runners.stackedImages` is on, which
  requires every host of that rack, including borrowed ones, to run
  macOS 27 and Tart 2.36 or newer. Rented pools, explicit pools and any
  Xcode pinned by `imageTag` keep the standalone image.
- **One-off builds.** `runner-image.yml` with `stacked: true` builds the
  same image from a branch and pushes `:macos-<dashes>-<git-sha>-stacked`.

- **What it saves.** The base's chunks are the same blobs Layer 1
  publishes, and Tart keeps immutable disk files in a content store
  keyed by their digest. A host that holds the base pulls only the
  overlay: 1.6 GB for 26.6, against 23 GB of changed chunks for the
  standalone image.
- **Build mechanics.** The Packer plugin has no `--stacked`, so the
  job puts `stacked-tart/` first on `PATH`, which rewrites the plugin's
  `tart clone` to `tart clone --stacked`. A stacked VM has no
  `disk.img`, so `stacked = true` also keeps the recovery partition
  instead of deleting it. `clone --stacked` of a standalone base
  hashes the whole base disk (about a minute for 140 GB) on every
  build.
- **First push per base.** Tart checks the target repository for the
  base's blobs and does not mount them from `macos-tahoe-xcode`, so
  the first stacked push on a new Layer 1 uploads the base once.
- **Lineage.** Always stack on Layer 1, never on a previous runner
  image: every extra overlay is one more file to validate and open at
  boot, and DiskImageKit cannot merge layers.

## Active profiles + the default

Active profiles are the single source of truth in
`infra/runner-image/profiles.json` — a JSON array, newest first:

```json
// infra/runner-image/profiles.json
["27.2-beta", "27.1", "27.0", "26.6", "26.5", "26.4.1", "26.3", "26.1.1", "26.0.1"]   // newest first
```

Beta entries follow the `<major>.<minor>-beta` shape (matching the
mirror + base image tags `xcode-xips:27.2-beta`,
`macos-tahoe-xcode:27-2-beta`), so `runs-on: tuist-macos-27-2-beta`
resolves to a runner pool sized by
`runnersFleet.xcodeOverrides["27.2-beta"]`. Release candidates use
`rc` (`27.1 Release Candidate` → `27.1-rc`), which is also the
channel a later `Release Candidate 2` moves. The longer
`release-candidate` would push the 12 vCPU shape pool's
`tuist.dev/runner-pool` label past Kubernetes' 63-character limit.

Xcode 27.1 RC retirement removes RC builds and pools and the temporary
stable bootstrap pin only after the additive chart is deployed and a
versioned release includes stable. Keep the bootstrap image for rollback.
The default stays 26.6. Follow the [retirement runbook](xcode-27.1-retirement.md)
for merge prerequisites and required post-rollout reconciliation, including
profiles saved by old replicas and jobs requeued after their claims release.
Use the documented release `eval` with `Ecto.Migrator.with_repo/2` for this
reconciliation; `rpc` is unavailable when release distribution is disabled.

The file lives under `infra/runner-image/**`, so editing it triggers
a runner-image release. Adding a profile builds only that profile;
removing one drops it from the next release.

- **Active.** Every release publishes a `:macos-<dashes>-<semver>` tag
  for each entry, rebuilt or carried over as the plan decides.
- **Default profile.** The first entry, by convention. Which
  version `runs-on: tuist-macos` actually resolves to is the
  catalog entry marked `default: true` in
  `runnersFleet.xcodeVersions`, so moving the default means editing
  both this list and that catalog.
- **Out-of-rotation profiles.** Any other `:macos-<dashes>` tag
  that's been published in the past and still exists in GHCR. They
  don't refresh on runner-image releases — customers can keep pinning to them, but new runner-agent /
  dispatch-loop / launchd changes only land in them when the
  operator explicitly refreshes via

      gh workflow run runner-image.yml -f xcode_version=26.X.Y

  That dispatch path doesn't move the chart pin.

Active rebuilds always produce both an immutable tag
(`:macos-<dashes>-<semver>`, the one deploys resolve to a digest) and a rolling
tag (`:macos-<dashes>`, convenient for humans pulling "latest in
this profile").

Bumping the Xcode customers see on their runners:

1. Publish a Layer 1 image with the new Xcode — first run
   `mise run xcode-mirror:upload 26.X.Y` on a maintainer Mac to put
   the .xip into `ghcr.io/tuist/xcode-xips:26.X.Y`, then
   `gh workflow run macos-xcode-image.yml -f xcode_version=26.X.Y`.
   See `infra/macos-xcode-image/AGENTS.md` for the runbook.
2. Edit `infra/runner-image/profiles.json`: add the new Xcode as an
   additional entry (most common — gives customers it alongside the
   existing default), or put it first to make it the newest / default
   profile. **If you move the first entry, also bump
   `server-production-deployment.yml`'s xcresult-processor
   `XCODE_VERSION` to match** — that image must be at least as new
   as the newest runner profile.
   Commit with a `feat(runner-image): ...` message so the release
   builds the new profile. Once that `runner-image@` release is
   published, add the matching `runnersFleet.xcodeVersions` entry in
   `values-managed-common.yaml` so the fleet renders a pool for it.
3. Once customers have migrated off an older Xcode, drop its entry
   from `profiles.json` (and its `values-managed-common.yaml` pool).
   The `:macos-<dashes>` tag stays in GHCR for any lingering pin; the
   dispatch path above stays available for a one-off refresh if
   security work needs to land there.

### Betas enter as a channel

Xcode betas sit in `profiles.json` like any other profile, but the
entry is a **channel** (`27.0-beta`), not a beta (`27.0-beta-6`).
Two things fall out of that, both wanted:

- The base image `macos-xcode-image` publishes for a beta carries
  both an exact tag and the channel tag, so moving a beta is a
  rebuild of `:27-0-beta`. The entry here already points at it,
  which makes a beta bump a zero-diff change: publishing the channel
  dispatches a runner-image release that rebuilds that profile.
- The channel is what customers' Runner Profiles store in
  `xcode_version`. Retiring a catalog entry a profile still names
  strands it on a RunnerPool that no longer renders, and a
  stranded macOS profile queues its jobs forever rather than
  failing them. A channel outlives the betas behind it, so that
  never comes up.

A beta profile is rebuilt when its channel moves or the image's
sources change, and `fail-fast: true` on the matrix means a beta base
that cannot take the runner layer would abort its siblings. That layer is thin
(runner agent plus launchd, ~2 min) and the risky Xcode work all
happens in Layer 1, which fails in `macos-xcode-image` instead, so
the exposure is small. Full runbook: "Promoting an Xcode beta" in
[`../macos-xcode-image/AGENTS.md`](../macos-xcode-image/AGENTS.md).

## Profile tagging

Push tags are per-Xcode-profile: `:macos-26-4-1` (rolling, latest
in that profile) plus `:macos-26-4-1-<semver>` (immutable, for
rollbacks and traceability). The tag form is the Xcode version
with dots → dashes, matching Layer 1's tag scheme: a 26.4.1 Layer
1 produces a `:macos-26-4-1` runner image, a 26.5 Layer 1
produces `:macos-26-5`. Pools run the digest of the immutable
per-release tag (`:macos-<profile>-<semver>`), so multiple Xcode profiles can
coexist in GHCR — the runner-fleet config currently selects one as
the default but the structure is ready for the future
customer-facing profile selection.

## How it ends up serving traffic

1. Each catalog RunnerPool's `spec.image` (`tuist.macosRunnerImage`)
   is `ghcr.io/tuist/tuist-runner@<digest>`, the digest the deploy
   resolved for the profile's immutable per-release tag
   (`:macos-<profile>-<semver>`) from GHCR the way hosts pull it. An
   `xcodeOverrides[].imageTag` pin renders as that tag instead.
2. `Tuist.Runners.Reconciler` creates a Pod with this image as
   `spec.containers[0].image`; tart-kubelet on the target Mac
   mini calls `tart pull`/`tart clone`/`tart run`.
3. The VM boots, auto-login brings up runner's desktop session,
   loginwindow loads the LaunchAgent, and the agent's entrypoint
   runs `inject-env.sh` then `dispatch-poll.sh`. The dispatch
   script exchanges the projected SA token for a JIT config (200
   with the JIT when a queue row is claimed, 204 while idle),
   runs the GitHub Actions runner single-shot, traps the exit,
   halts the VM. tart-kubelet sees `tart run` exit, the Pod goes
   Succeeded, the RunnerPoolReconciler reaps the Pod + sibling
   SA and boots a replacement to keep the pool at
   `spec.replicas`.

   The trap writes its exit code to `runner-rc` in the `status`
   share on its way out, and tart-kubelet publishes that as the
   Pod's terminated container state. Nothing else carries it off
   the guest: the trap halts the VM on *every* path, so `tart run`
   exits zero whether the job finished or the runner died on boot,
   and a macOS runner death otherwise reaches the cluster as a
   bare `Succeeded` with no exit code, no reason and no log. Three
   consumers in the runners-controller read that field — the
   `runner pod terminated` forensics line, the abnormal-end
   death-log capture, and the `finishedAt` that dates the billing
   session — and all three were Linux-only until the guest started
   reporting. Written from inside the trap rather than after the
   runner exits, so it also covers the aborts that never reach a
   runner. Absent on hosts with no `status` share (it rides on the
   cache-volume feature), which the host reports as
   `TartRunExited` rather than laundering tart's zero into a clean
   runner exit.

   The exit code alone is not enough, because it does not separate
   the two cases that matter: a runner that finished its job and a
   runner that halted without ever taking one both report 0. So the
   trap also publishes `runner.log` — `dispatch-poll.sh`'s own
   output — into the same share, and tart-kubelet re-emits a bounded
   tail of it to its own stdout before teardown deletes the share.
   That stdout is already tailed by the host log shipper, so the
   trail reaches Loki without the shipper having to discover
   per-VM shares. Copied from the trap rather than `tee`d as the
   script runs, so a still-running tee cannot flush a duplicate tail
   after the copy. Same `status`-share dependency as `runner-rc`:
   pools with cache volumes off keep the old behaviour of logging
   only inside the guest, and a guest killed before its trap runs
   publishes nothing — that case already arrives distinguishably as
   `TartRunExited`.

   Both of those describe a runner that *ended*. `runner-heartbeat`
   in the same share covers the runner that does not: the poll loop
   rewrites it every iteration with the state it is in (`polling`
   while warm, `claimed` once it takes a job), and the file's mtime
   is the beat. It exists because a macOS Pod's phase and Ready
   condition are synthesized from "the VM process is alive and has
   an IP" — tart-kubelet runs no container probes — so a guest whose
   poller died reads 1/1 Running for the rest of the VM's life, and
   nothing bounds that life: warm standby is deliberately unbounded
   and in practice a warm macOS runner is recycled only when its SA
   token expires around the 8h mark. tart-kubelet publishes the beat
   as the `tuist.dev/runner-heartbeat-state` and
   `tuist.dev/runner-heartbeat-at` Pod annotations and the
   runners-controller stops counting a stale one as warm capacity.
   `claimed` is written once and then never refreshed — from there
   the script is blocked in `wait` on `run.sh` — so it is the state,
   not the age, that marks the Pod busy; it also does so
   independently of the server's best-effort owner label. Same
   `status`-share dependency as the two above, and the absence is
   read as "no signal" rather than "dead", so a pool with cache
   volumes off keeps counting as capacity.

For the customer-facing dispatch label and capacity model see
`server/lib/tuist/runners.ex` and `infra/helm/tuist/values.yaml`
(`runnersFleet.pools[]`) — they're the right place for routing
semantics; this doc is just about the VM image.

## GitLab CI

`/opt/tuist/tuist-gitlab-runner` executes a server-acquired GitLab job with the upstream shell executor. Its source is in `infra/linux-runner-image/gitlab-runner/` and the shared `build-runner-image-binaries` action builds its darwin/arm64 binary for Packer. Dispatch stages the assignment as private JSON and reuses the normal VM lifecycle. Reusable GitLab runner tokens never enter the VM.

- GitLab parsing uses `/opt/homebrew/bin/jq`, checked before acquisition independently of launchd PATH. Stage assignments in a private `mktemp` file and atomically rename only after successful parsing; failures remove temporary credentials and terminate the claimed runner.

- macOS custom volumes reuse the shared runner-cache lifecycle with an APFS
  backend; rollout and compatibility are documented in `infra/tart-kubelet/custom-cache-volumes.md` at repository root.

- The job-started hook runs `tuist-cache-volume --checkout "$GITHUB_WORKSPACE"`
  before the first step. It mounts the job's cached checkout only when the host
  serves one, the workspace is empty and its parent holds nothing else, and
  otherwise leaves it untouched, so actions/checkout clones as before. It never
  fails the job. The image mounts at the workspace's parent and the guest moves
  the tree into the workspace: the workspace must not be a volume root, because
  Foundation stages safe saves in `<volume root>/.TemporaryItems` and Xcode's
  task sandbox refuses writes there inside the project (CoreML compilation into
  a DerivedData under the workspace fails with "compile failed to write partial
  plist"). `tuist-cache-volume --key` leaves out a path in the mounted
  checkout's `.git` that already holds data (such as `.git/lfs`) with a notice,
  instead of refusing it as non-empty.
  When the host granted a checkout (mounted, or `cold`, `capacity`, `timeout`)
  it records the workspace and the mounted master's commit and LFS objects in
  `/Users/runner/.tuist-checkout.json`. The teardown then runs
  `tuist-cache-volume --checkout-export`, which packs what the job's checkout added
  (the job commit and the objects of its tree the master's tip tree lacks; see
  `infra/linux-runner-image/AGENTS.md`) and copies its new LFS objects into the share's `checkout-export/` (45 s budget)
  for the host to verify and build from. Neither step fails the job.

- Failed custom-volume detach must emit a warning that publication is skipped;
  preserve the job's exit status and never force-detach a publishable image.
