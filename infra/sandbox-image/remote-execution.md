# Linux Bazel remote execution

The first rollout is an account opt-in. The `bazel_remote_execution` flag defaults
off in **every** environment, including development and staging. There is no
automatic account enrollment. An operator configures capacity and enables the
flag for that account after validating the complete deployment.

## Architecture

Bazel keeps using Kura for CAS, action caching, dependency downloads and build
events. A separate `reapi-gateway` serves `Execution.Execute`, `WaitExecution` and
execution capabilities. Configure both `--remote_cache` and `--remote_executor`;
the gateway does not duplicate Kura's storage APIs.

The gateway forwards the client's scoped cache bearer credential to the server.
The server verifies it and requires **both read and write grants for the project**
plus the account feature flag for submission. Reading an existing operation does
not require the flag, so active builds drain after it is disabled. The account
metadata header selects a scope; it does not authenticate it.

Before submitting, the gateway reads the action, its command, the input tree and
small files from Kura with the client's credential, within 50 ms and 255 KiB. It
asks for all of them with the action in one `BatchReadBlobs`, through Kura's
`x-tuist-action-inputs` header. A cache that returns the action alone gets the
input tree read with one `GetTree` call beside the command (three round trips),
and one without `GetTree` is walked one level per round trip. The
server passes those blobs to the action's VM, which uses only the ones that match
their digests and reads anything else from Kura itself. A failed or partial read
only means the VM fetches more. Operations queued behind the account's
concurrency drop their prefetched blobs.

### Scheduling

Each account has one `Tuist.RemoteExecution.Scheduler` process in the server
cluster, registered under a `:global` name and started by the account's first
request. Any replica forwards requests to it over Erlang distribution. The
scheduler holds the account's queue, operations and VM assignments in memory.
**No per-action state is persisted.** Submission, dispatch and result delivery
involve no database writes.

Losing the scheduler (replica restart, crash, netsplit) loses its queued and
running operations. The gateway then reports the operation as unavailable or
`NOT_FOUND`, and Bazel executes the action again on a new scheduler. Actions must
therefore be safe to re-run, which hermetic Bazel actions are. Identical in-flight
actions of the same project (same action digest, cache lookup not skipped) share
one operation, so those retries attach to the running execution when they reach
the same scheduler.

A submission waits up to five seconds for its result, so most actions need one
gateway request. Longer actions continue with five-second `WaitExecution`-style
long polls that return as soon as the state changes. Completed operations stay
readable for one minute. Queued operations fail after 15 minutes. The queue is
bounded to four times the account concurrency, at most 512 actions; a full queue
returns `RESOURCE_EXHAUSTED`.

### Leases

While a project is active, each gateway replica holds one **lease** for it: a
prepared VM whose node waits for the gateway to claim it. The gateway runs the
project's next action by claiming that VM directly on its node with the
action request, and receives the result from the node, without a server
request. Queued operations take ready VMs before leases. The scheduler grants a
lease by sending the node an `exec` that waits for a single-use nonce, which
only the gateway receives; the project credential stays on the node. The
pending `exec` ends when the action finishes, which retires the VM, or after
30 seconds unclaimed, which returns the untouched VM to the pool. The gateway
stops using a lease five seconds before that and replaces each lease once
used or expired, until the project has been idle for a minute.

The gateway uses a lease only for a credential the server accepted for the
project in the last ten seconds, and never past the credential's expiry, the
same decision reuse as the server's. Other credentials, projects without a
lease and refused claims go through the server. Identical in-flight actions
do not share an operation on this path, and `WaitExecution` for its operations
returns `NOT_FOUND`, which Bazel answers by executing again. The server
advertises leases in the capabilities response; nodes serve claims on
`DIRECT_EXEC_ADDR`, reachable only from gateway Pods.

### Account concurrency

`max_concurrency` bounds the account's **VMs**, not its actions. Every VM has a
`sandboxes` row (`purpose = remote_execution`) inserted under an account advisory
lock before the VM is created and deleted only after the node acknowledges VM
deletion. Creating, idle, busy and uncertain VMs therefore all occupy a slot
across every scheduler and replica, even when two schedulers briefly coexist.
Zero concurrency stops admission. Lowering the limit drains existing VMs.

The scheduler renews its rows' leases in one batched update every 20 seconds
(60-second lease). It assigns a VM only while its last renewal is under 40
seconds old, so a scheduler that cannot reach PostgreSQL stops dispatching
before its lease lapses. The minute `MaintenanceWorker` deletes the VMs of rows
whose lease lapsed and then the rows; failed deletions retry on the next run.
A stopping scheduler expires its leases immediately so the next run reclaims
them. A create carries a node-enforced deadline (120 seconds) shorter than a new
row's first lease (190 seconds), so reaping never races a create still in flight.
An unconfirmed create holds its slot until that deadline has passed.

### VMs and warm pool

Each action gets a fresh Firecracker VM, destroyed after that action and never
reused. The scheduler keeps `busy + queued + warm` VMs (capped at
`max_concurrency`) by reserving and preparing new ones in the background. A
prepared VM holds only the pristine image and workspace. It receives a CAS
credential and action data only when the scheduler assigns it to one action.
Idle VMs beyond the warm target, and VMs whose image or node no longer matches
the settings, are retired. Failed preparation backs off for five seconds. When
no node has room, nothing is created: the scheduler retries once one of the
account's placed VMs is deleted, or on its five-second tick.

Preparing a VM connects it to the CAS endpoint and executes one throwaway action
through the guest worker, against a CAS server inside the guest. A VM restored
from the template snapshot faults in each memory page on first touch; this moves
that cost off the admitted action. Nothing leaves the guest and no credential
exists yet.

`warm` follows demand: the number of actions that arrived within the last
preparation time, plus one. That is how many VMs are consumed while a
replacement is prepared, so a burst of short serial actions keeps finding a
ready VM. The scheduler measures preparation time as a moving average of its own
preparations. A build's peak is held for one minute so the pause before the next
build does not drain the pool; after that, `warm` falls to the current demand and
idle VMs are retired. `warm_pool_size` caps `warm`.

A used VM keeps its slot until the node confirms deletion, and its replacement
takes about as long again to create and prepare. A serial chain of short actions
therefore needs several times more slots than it has actions in flight: in the
native benchmark, about ten slots kept every action of an eight-action chain on a
prepared VM.

The scheduler issues one project cache credential (30-minute TTL) and reuses it
for that project's VMs while at least 13 minutes remain. Each VM is single-use
and the credential has the same scope as the client's, so reuse does not widen
what any action can reach.

`warm_pool_size` is an opt-in account setting, default zero and capped at eight:
the most VMs the scheduler may keep warm for the account, not a fixed count.
Idle VMs consume real memory and disk: set it only as high as the account's
reserved hosts have budget for.

### Action cache

Only successful, cacheable actions (exit code zero, `do_not_cache` unset) are
stored in the action cache, after their outputs are in CAS. The guest reports
whether a result is cacheable. The gateway sends the result to Bazel first and
then publishes the action-cache entry to the account's Kura with the client's
credential, in the background. Publication is best-effort: a gateway restart or
saturation (256 pending publications) drops it, which only costs a later cache
miss. Bazel does not depend on the entry; dependent actions read outputs from CAS.

### Guest isolation

A root `sbx-executor` in the guest downloads verified input blobs, drops the
command to UID/GID 1000 with an explicit environment, and uploads outputs and
logs to the project's CAS. It never looks the action up in the action
cache: Bazel checks it before calling `Execute`. The build does not inherit
the CAS token. Linux `no_new_privs` prevents setuid/file-capability
escalation. It is applied on a locked OS thread through the command's
fork/exec; CAS waits must not move execution to a thread without
`no_new_privs`. The guest agent accepts only
host-CID vsock connections. This is VM isolation for untrusted code, not network
hermeticity: the initial policy permits public HTTPS and the scoped cache and
control services.

The trusted Bazel template formats and unmounts an empty workspace once before
snapshotting. Equal-size action workspaces are private reflinks of that image.
The template's optional `sbx-template-prepare` hook warms image-owned executor and
compiler pages before any credentials or inputs arrive. Used VMs, disks and
action caches are never incorporated into the template. Pin a new template tag
when changing the image.

An image build option, `--build-arg EMBEDDED_EXECUTOR=1`, runs the executor inside
the guest agent's already-started Go runtime. It defaults off. Only the exact host
request for `/usr/local/bin/sbx-executor` uses this path. An exclusive
`/run/tuist-executor.claim` file permits one invocation and survives an agent
restart. Credentials arrive after assignment and stay in root process memory. The
executor uses a dedicated locked OS thread for `no_new_privs` and terminates that
thread afterward. Roll it out only through an enabled account's image pin.

A pristine guest also accepts `/usr/local/bin/sbx-executor --prepare-cas ENDPOINT`,
which establishes only a transport connection, bounded to three seconds, for the
action that later consumes it. It carries no credentials. An endpoint change
closes it before using the new endpoint. Older images or failed handshakes fall
back to dialing at action time.

Outputs include executable files, relative symlinks and directory trees. A
nonzero command exit is an ordinary `ActionResult`; a timeout or infrastructure
failure is an `ExecuteResponse` status. Only the small result protobuf crosses
the control channel; sources, outputs and logs go directly between the guest and
Kura. Empty logs have neither inline bytes nor a CAS digest.

Supported execution properties are exactly `OSFamily=Linux`, `Arch=amd64` and
`tuist-image=sha-<commit>`. The image property participates in the action digest
and must match the template tag of the VM that runs it; actions pinned to a
previous image fail with `FAILED_PRECONDITION` after the account's image changes.
Use a Linux execution platform and compatible hermetic toolchains.

## Capacity and failure semantics

A CI job holds its runner while its remote actions run. If those actions
compete with queued CI for the same memory, a burst of CI jobs can fill the fleet
and leave every job waiting on actions that have nowhere to run. Workers
therefore always have capacity CI cannot take back, in one of two modes:

- **Dedicated hosts** excluded from every CI RunnerPool, with the
  `tuist.dev/workload=remote-execution` label and matching `NoSchedule` taint.
  Each worker has a fixed CPU/memory reservation of `perNodeConcurrency` slots.
- **Shared runner hosts** (`workers.sharedHosts`), named Linux runner hosts that
  also run CI and the agent sandbox daemon. Each worker holds an elastic memory
  carve-out like the agent daemon's, bounded by a floor and a ceiling:
  - The Pod starts at `floorSlots` (request equals limit). Runner Pods never get
    that memory, and execution placement uses it, and anything the Pod has
    grown to, without a runners-controller grant, so a CI burst cannot starve
    the actions its jobs wait on.
  - When no VM fits, the server grows the Pod in place, in whole GiB, toward
    `ceilingSlots`. Unlike agent sandboxes, which only take memory the grant
    offers, the worker asks even when the grant offers nothing beyond what it
    holds (every runner busy): its actions serve jobs that are already running.
    The kubelet defers a growth that does not fit and the scheduler keeps
    counting it, so no new runner Pod lands on the room that finishing jobs
    free until the growth applies. Running jobs are never evicted.
  - A revoked, expired or missing grant still refuses growth. CI host
    reservations, unhealthy nodes and a stopped controller keep their
    protection, and a reservation shrinks the carve-out back to what its VMs
    hold, never below the floor.
  - Grown carve-outs shrink back toward what their VMs hold 15 seconds after
    the last growth.

  The worker connects to the server as `<node>.remote-execution`, beside the
  node's agent daemon, which connects as the node itself. The runners
  controller recognises `tuist.dev/remote-execution-daemon` Pods, keeps their
  memory out of runner seats and publishes their grants under that name. The
  controller release with that support must run before enabling shared workers.
  Configure the suffixed names as the account's `node_names`.

The [chart](../helm/remote-execution/values.yaml) publishes `EXECUTION_SLOTS`
(the ceiling on shared hosts). Placement also requires an operator-configured
node name, the matching image, memory/disk capacity, and the daemon's
`execution_deadlines` capability; old daemons are rejected. Each slot is 2 vCPUs,
4 GiB guest RAM, 64 MiB VM overhead and a 10 GiB workspace; the daemon reserves
another 512 MiB. On shared hosts only the floor's CPU is requested; guests above
it use idle cores. Disk budgets must cover templates, rootfs clones, workspaces
and host headroom, and on shared hosts must leave room beside the agent daemon's
budget and runner caches on the same filesystem. Workers jail guests from UID
30000 so their jails never share a UID with the agent daemon's.

Disconnecting a client does not cancel its operation. The API does not implement
Operations cancellation or priorities. Execution lasts at most ten minutes, with
bounded staging and upload time. Synchronize server and host clocks; lease and
create deadlines include five seconds of skew slack. The daemon overlaps network
removal and VM termination, waits for both, then removes files and releases its
slot. An unreachable node keeps its VMs' slots until it reconnects and deletion
succeeds; node orphan reconciliation removes VMs whose rows are gone.

Per-action bounds: 4 MiB protobuf metadata, 1 GiB individual blob, 8 GiB combined
input/output transfer, 50,000 filesystem entries, depth 128, 64 MiB per log and
128 KiB result protobuf. Exceeding a bound fails explicitly. The gateway permits
128 concurrent requests/streams per replica.

## Build and rollout

1. Run the PostgreSQL migration and deploy the server with the flag off.
2. Choose hosts as described above: provision dedicated hosts, or name shared
   runner hosts in `workers.sharedHosts` after the runners controller release
   that recognises remote execution workers is deployed. Confirm the
   environment's `values-managed-<env>.yaml` in the
   [chart](../helm/remote-execution/) names the right server namespace and
   gateway host. Set `enabled: true` there.
3. Run **Remote Execution Deployment** (`.github/workflows/remote-execution-deployment.yml`)
   for the environment. It publishes the guest template and the execution gateway
   (`ghcr.io/tuist/tuist-remote-execution`, both under the sandbox image's
   source-derived tag) and sandboxd, or takes published tags, then installs the
   release into `tuist-sandboxes`. The gateway's Ingress uses the dedicated
   `nginx-grpc` controller with TLS and a 16-minute proxy timeout, DNS-only like
   the other gRPC hosts. The gateway must reach the accounts' Kura endpoints to
   publish action-cache entries. Upgrades replace gateways; workers roll out
   `OnDelete` (see Rollback). The server's network policy admits pods labelled
   `tuist.dev/remote-execution` from the sandbox namespace.
4. Confirm hosts report `execution_deadlines: true`, `execution_slots > 0`, and a
   ready `bazel` template with the pinned tag. Confirm fixed CPU/memory requests
   and the dedicated host taint, or on shared hosts the floor-sized workers and
   their grants (`tuist_runners_sandbox_memory_bytes{node="<node>.remote-execution"}`),
   and disk headroom before allowing any account.
5. In an authorized operator release console, configure the account:

   ```elixir
   account = Tuist.Accounts.get_account_by_handle("tuist")
   Tuist.RemoteExecution.configure(account, %{
     max_concurrency: 2,
     node_names: ["<reserved-linux-node>"], # shared hosts: "<node>.remote-execution"
     image_tag: "sha-<template-commit>",
     cas_endpoint: "grpcs://<the-account-kura-endpoint>",
     executor_endpoint: "grpcs://<execution-endpoint>"
   })
   FunWithFlags.enable(:bazel_remote_execution, for_actor: account)
   ```

   Change concurrency independently with
   `Tuist.RemoteExecution.configure(account, %{max_concurrency: 4})`. A running
   scheduler picks up configuration changes immediately and flag changes within
   30 seconds. The endpoint must be the same project CAS that the client uploads
   into; update it when account cache placement changes.

6. Configure a Linux Bazel workspace:

   ```sh
   tuist bazel setup --remote-executor grpcs://<execution-endpoint> \
     --execution-image sha-<template-commit>
   bazel test //... --spawn_strategy=remote --noremote_local_fallback
   ```

   `GET /api/remote-execution/<account>/<project>/capabilities` returns the
   configured image, endpoint and concurrency to an authorized caller. If a
   project's execution platform supplies `exec_properties`, put all three
   properties there: Bazel only uses default properties for platforms without
   their own. Re-running setup without the execution options opts the workspace
   out.

## Observability

The **Tuist Remote Execution** dashboard (`infra/grafana-dashboards/remote-execution.json`)
reads three sources, none labelled by account or project:

- Gateways export `reapi_gateway_*` on port 9090: Execute calls by path (`lease`
  or `server`) and final status, Execute latency, how inputs were prefetched,
  action-cache publication outcomes and admitted streams.
- The server exports `tuist_remote_execution_*` through PromEx: submissions
  (accepted, deduplicated, `queue_full`), operation outcomes, duration and queue
  time, VM preparation time by outcome, and lease outcomes. Leased executions
  bypass the scheduler, so they appear only in the gateway metrics.
- Worker daemons export the existing `sandboxd_*` metrics on port 9090.

Four warning rules cover failing Execute calls, refused submissions, failing VM
preparation and timed-out leases. They are recorded in
[`remote-execution-alert-rules.json`](../helm/k8s-monitoring/remote-execution-alert-rules.json)
and documented in [alerts.md](../helm/k8s-monitoring/alerts.md#remote-execution-rules).
Create them in Grafana before enabling the first account. Merging the file
does not provision them.

## Rollback

Disable the account flag and set concurrency to zero. The scheduler fails queued
actions, retires idle VMs and lets running actions finish. Wait until the
account has no `sandboxes` rows with `purpose = remote_execution`; an unreachable
host is not evidence that its VMs stopped. The workers use `OnDelete` rollout:
update images only after draining, then replace daemon Pods through the
authorized deployment workflow. Keep the additive migration during a code
rollback. Do not drop its table or columns while server replicas or executor VMs
use them.

Server deploys restart schedulers: in-flight actions on a stopping replica fail
and Bazel re-executes them on the next scheduler, and the stopped scheduler's VMs
are reaped within a minute.
