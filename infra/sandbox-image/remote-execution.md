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
reused. The scheduler keeps `busy + queued + warm_pool_size` VMs (capped at
`max_concurrency`) by reserving and preparing new ones in the background. A
prepared VM holds only the pristine image and workspace. It receives a CAS
credential and action data only when the scheduler assigns it to one action.
Idle VMs beyond the warm target, and VMs whose image or node no longer matches
the settings, are retired. Failed preparation backs off for five seconds.

The scheduler issues one project cache credential (30-minute TTL) and reuses it
for that project's VMs while at least 13 minutes remain. Each VM is single-use
and the credential has the same scope as the client's, so reuse does not widen
what any action can reach.

`warm_pool_size` is an opt-in account setting, default zero and capped at eight.
Idle VMs consume real memory and disk: opt in only for accounts whose reserved
hosts have that budget.

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
logs to the project's CAS. The build does not inherit the CAS token. Linux
`no_new_privs` prevents setuid/file-capability escalation. It is applied on a
locked OS thread through the command's fork/exec; CAS waits must not move
execution to a thread without `no_new_privs`. The guest agent accepts only
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

Use reserved hosts excluded from **every CI RunnerPool**. Give them the
`tuist.dev/workload=remote-execution` label and matching `NoSchedule` taint through
the normal host-provisioning workflow. This avoids the dependency cycle where a
CI job holds its runner while its remote actions wait behind queued CI jobs.

The standalone [chart](../helm/remote-execution/values.yaml) gives each host fixed
CPU/memory reservations and publishes `EXECUTION_SLOTS`. Placement also requires
an operator-configured node name, the matching image, memory/disk capacity, and
the daemon's `execution_deadlines` capability. Shared or elastic sandbox nodes
and old daemons are rejected. Each slot is 2 vCPUs, 4 GiB guest RAM, 64 MiB VM
overhead and a 10 GiB workspace; the daemon reserves another 512 MiB. Disk budgets
must cover templates, rootfs clones, workspaces and host headroom.

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
2. Build sandboxd with its existing image workflow. The sandbox-image workflow
   validates the guest template and execution gateway builds on pull requests.
   To build the gateway locally:

   ```sh
   docker build --platform linux/amd64 --target execution-gateway \
     -t ghcr.io/tuist/tuist-remote-execution:sha-<commit> infra/sandbox-image
   ```

3. Install the standalone chart into the **existing** sandbox namespace configured
   on the server. Pin gateway, sandboxd and template images. Set `serverURL` to
   the in-cluster server URL. Configure TLS/HTTP2 ingress for its gateway Service
   using the environment's existing gateway; do not expose plaintext gRPC
   publicly. Ensure its idle/request timeouts allow a 15-minute execution stream.
   The gateway must reach the accounts' Kura endpoints to publish action-cache
   entries. The chart is disabled by default and does not alter managed
   environments.
4. Confirm hosts report `execution_deadlines: true`, `execution_slots > 0`, and a
   ready `bazel` template with the pinned tag. Confirm fixed CPU/memory requests,
   disk headroom, and the dedicated host taint before allowing any account.
5. In an authorized operator release console, configure the account:

   ```elixir
   account = Tuist.Accounts.get_account_by_handle("tuist")
   Tuist.RemoteExecution.configure(account, %{
     max_concurrency: 2,
     node_names: ["<reserved-linux-node>"],
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
