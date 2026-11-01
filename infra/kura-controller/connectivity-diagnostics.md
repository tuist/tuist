# Connectivity diagnostics through read-only pod logs

Optional Kura telemetry publishes resolver configuration and bounded DNS/TCP/HTTP
header timings from selected instances. Operators read the existing `kura`
container logs through their existing `pods/log` permission. Equipped pods read
an expiring live-Pod annotation through a fixed read-only DownwardAPI projection.
Activation, removal and expiry do not change the StatefulSet template. There is
no diagnostic sidecar, listener, runtime API client, RBAC change or gateway
bypass. Preparation defaults off and instance selection remains empty.

## Motivation and fixed scope

During the South America connectivity investigation, the normal production
identity could read pods and logs but could not execute `cat /etc/resolv.conf` or
an unauthenticated `curl` against the internal server's `/ready` endpoint.
Human-approved diagnostics subsequently measured about 0.91 seconds for DNS and
about 1.14 seconds cumulatively through TCP setup in both affected replicas.
The one-second connect budget failed while three seconds succeeded. An absolute
DNS name also succeeded within one second. The timeout fix is PR #13112; this
feature adds observations and does not change application client timeouts.

Only three compiled profiles exist:

| Profile | Fixed HTTP destination |
| --- | --- |
| `production` | `tuist-tuist-server.tuist.svc.cluster.local:80/ready` |
| `staging` | `tuist-tuist-server.tuist-staging.svc.cluster.local:80/ready` |
| `canary` | `tuist-tuist-server.tuist-canary.svc.cluster.local:80/ready` |

Every profile also observes the fixed Alloy OTLP HTTP receiver at
`k8s-monitoring-alloy-receiver.observability.svc.cluster.local:4318/v1/traces`.
These are unauthenticated GET requests, not span exports. A receiver's expected
405 response proves only that HTTP headers returned, not that it accepts or
forwards spans. The worker never reads the configured exporter endpoint or its
credentials, so an instance overriding that endpoint may export elsewhere.

The server route maps GET `/ready` to `TuistWeb.PageController.ready/2`, which
returns an empty HTTP 200. Every cycle compares the normal name and the
trailing-dot absolute name, each with one- and three-second combined DNS/TCP
budgets, followed by the normal and absolute Alloy names with three-second
combined DNS/TCP budgets. No configurable URL, path, method, header, command,
timeout, or frequency is accepted. New destinations require a reviewed code
change.

## Lifecycle and resource bounds

A regular sidecar was rejected because its crash or image-pull failure makes the
whole Pod NotReady, removing an otherwise healthy Kura replica from Service
endpoints. The implementation instead starts an optional worker before Kura's
bootstrap, on a dedicated OS thread with its own current-thread Tokio runtime.
It receives only the fixed selection file, with no application state, readiness
handle, store, or authenticated client. Application startup does not await a
sample or propagate diagnostic errors. Unwinding worker panics are caught.
Missing/invalid configuration disables sampling; thread creation failure skips
the worker and runtime creation failure stops only diagnostics. There is no
additional image to pull or container whose status can affect Kubernetes readiness.

`KURA_CONNECTIVITY_CONFIG_FILE` must equal `/etc/kura/connectivity/selection.json`.
The controller reserves this variable and the annotation
`kura.tuist.dev/connectivity-diagnostics`. The directory is projected without
`subPath`, so kubelet can refresh it. The runtime polls every five seconds and
accepts at most 512 bytes containing only a compiled `profile` and an absolute
`expires_at_unix_seconds`. A missing, unreadable, malformed, expired or more than
24-hour selection disables sampling. Kubelet propagation is eventual: activation
and early removal are not instantaneous. Once accepted, a monotonic deadline
cancels async sampling even if the controller/API is unavailable or the wall
clock moves backward. Configuration changes preserve the DNS permit and a
60-second cooldown, so toggling selection cannot accumulate DNS jobs or bursts.

Dropping the worker guard signals cancellation without joining the thread.
Cancellation drops an in-progress async sample and prevents later profile work.
The worker shuts down its runtime without waiting for uncancellable libc DNS.
One permit, held inside the blocking resolver closure, limits outstanding DNS
work to one even after the async caller times out. A stuck lookup makes later
samples return a bounded DNS failure instead of accumulating threads.

The worker shares Kura's process, credentials, cgroup, and stdout. This is trusted
runtime telemetry, **not a credential-isolated sandbox**. Its code does not read
credentials or application data, but it has the same OS privileges as Kura.
Caught panics and bounded network errors do not provide isolation from process
abort, allocator exhaustion, or process-wide resource failures. A blocked log
sink or filesystem read can stall the telemetry thread; cancellation does not
interrupt synchronous I/O, and application shutdown never joins that thread.
Logs use the existing output pipeline and retention.

Other limits are explicit:

- Six serial samples, followed by a 60-second pause; no concurrent samples or
  catch-up bursts. Each sample has a five-second overall deadline. The two added
  Alloy samples add at most two GET attempts per minute and two five-second
  async deadline budgets per cycle. They reuse the same worker, DNS permit and
  response buffer bound; synchronous I/O can still delay the worker.
- One system-resolver lookup and at most one TCP dial per sample. At most 16
  answers are accepted. Every answer must be an RFC1918 IPv4 or IPv6 unique-local
  address on the target's fixed port (80 for the server, 4318 for Alloy);
  IPv4-mapped addresses are checked as IPv4. Loopback,
  link-local/metadata, public, unspecified, multicast, and scoped IPv6 answers
  fail closed, including mixed safe/unsafe answer sets. The first validated
  address is dialed directly, without another lookup or fallback.
- Fixed unauthenticated HTTP/1 GET, including the original trailing dot in Host
  and the non-default port for Alloy.
  No proxy handling, redirects, cookies, compression, connection reuse, or auth
  headers. A fixed 8 KiB buffer caps all response bytes read, with at most 64
  parsed headers. The first complete header block ends the sample. Bodies are
  neither drained nor parsed; any prefetched body bytes are discarded. An
  informational response is recorded and closed without looping over more 1xx
  responses. Response headers, bodies, and remote error strings are never logged.
- The fixed selection file is capped at 512 bytes. `/etc/resolv.conf` is capped
  at 4 KiB; its content is emitted at activation and on content/readability
  changes, not every cycle.
- One worker thread and at most one blocking DNS worker, with no new persistent
  storage. Diagnostic CPU is part of the existing Kura container's real resource
  consumption. Autosizing excludes other containers; it cannot separate this
  built-in telemetry from other Kura work.

These application limits do not cap kernel socket buffers, TCP retransmissions,
or libc/NSS resolver allocations and retries. The answer limit bounds the Rust
collection, not all work inside the system resolver.

## Read-only access boundary and tradeoffs

The Pomerium, kube-impersonator, and tuist-ops authorization path remains intact.
No exec, attach, port-forward, pod/service/node proxy, ephemeral-container, or
Secret access is added. Reading/following logs cannot trigger requests or alter
frequency. Deployment configuration selects exact KuraInstance names within the
controller's watched namespace; wildcard/prefix selection is unsupported. The
reserved environment settings are stripped from instance `ExtraEnv`, and the
reserved annotation cannot enter equipped templates through `podAnnotations`.
Only the live-Pod writer manages selection. It runs after serving reconciliation
and status publication under one two-second total budget; failures do not fail
serving reconciliation. Only trusted runtime/deployment changes can extend the
fixed request profile.

The fixed Service is intentionally private. DNS compromise could redirect its
unauthenticated GET to another private address; address validation does not
attest Service ownership. Existing network policies still apply. This is a
bounded observation stream, not a general request proxy or shell.

A separate Job would not necessarily share Kura's network namespace, resolver,
source IP, or egress shaping. A namespace-entering host agent or privileged exec
broker would create a much broader access boundary. Native restartable init
sidecars still participate in Pod readiness. Built-in telemetry preserves the
actual pod network path without another container lifecycle dependency. It
cannot report when the Kura process itself cannot start or has exited.

The system resolver uses the process's libc configuration, avoiding the previous
Go `StrictErrors` bias. These samples still are not exact replays of Kura's
production HTTP client: they omit TLS, authenticated calls, Happy Eyeballs,
address fallback, connection pools, and response-body timing.

Timings (`dns_ms`, `connect_ms`, `first_byte_ms`, `headers_ms`, `total_ms`) are
cumulative from sample start. Missing stages did not complete successfully.
`connect_ms - dns_ms` estimates TCP setup. `total_ms` ends after headers or an
error/deadline, not after body completion. `outcome: ok` means a final HTTP header
block was received; 302 or 503 is still a useful observation and does not assert
readiness. Stage errors are fixed strings. Each sample includes target hostname,
port, path, start time, budget and, when available, HTTP status.

For an approved incident rollout, select one affected instance and a control on
a different, unaffected node. Record pod/node placement and the runtime image,
then compare matching Alloy and server stages across the same UTC window.
An old runtime may emit only the four server samples; require the new port-4318
records before interpreting absent Alloy observations. Header success does not
replay POST serialization, pooled connections, body reads or downstream delivery.
Keep selection empty until the separate rollout is approved.

Customer, instance and node identifiers belong in the private incident record,
not public values, PR descriptions, commit messages or validation logs. For
identifying selections, set `kuraController.connectivityDiagnostics.existingSecret`
instead of the inline `instances` list. The existing Secret must be in the
controller namespace with an `instances` key containing comma-separated exact
KuraInstance names. Provision it through the approved private configuration
process before deploying the reference; a missing Secret or key prevents the
new controller pod from starting. The chart never creates or reads this Secret
and rejects configuring both selection sources. Kubelet resolves the value into
the controller environment; public manifests contain only its generic reference.
Changing Secret contents requires controller replacement to reload the value.
The Secret is not copied to the runtime pods, and no new RBAC is needed. Selection
also requires `connectivityDiagnostics.expiresAt`, an absolute RFC3339 timestamp
at most 24 hours ahead. Invalid configuration disables diagnostics without
preventing controller startup. Restarts do not renew the configured deadline.

## Rollout, acceptance, and rollback

This PR does not deploy or enable diagnostics. Use the normal reviewed deployment
process; no incident elevation is required to implement or read these logs.

1. Deploy this compatible controller with `prepare: false`, empty selection and
   no expiry. Record its immutable image as the **controller rollback floor**
   before any adoption. A same-image reconciliation preserves old templates,
   including legacy profile settings, and does not equip or roll existing pods.
   Do not combine this compatibility step with enabling preparation.
2. Separately enable `kuraController.connectivityDiagnostics.prepare`. It installs
   the inert projection only for new StatefulSets or an ordinary runtime image
   change. The runtime must support this selection file. Preparation alone must
   leave existing template hashes and Pod UIDs unchanged. Check for any existing
   reserved annotation before adoption. Do not force a runtime restart to gain
   incident coverage. Ordinary image upgrades still use their existing health,
   backfill and disruption controls; this feature cannot guarantee they are
   disruption-free. Operator `OnDelete`/partition holds remain authoritative.
3. Qualify an equipped synthetic instance in staging before incident activation.
   Use an approved private selection and short expiry, then verify multiple
   replicas receive the selection with unchanged StatefulSet templates, Pod UIDs,
   container restarts and readiness. Confirm samples start, stop on removal and
   expire without controller updates. Include unavailable targets, configuration
   churn and a stuck DNS operation. Compare serving load, CPU, memory, disk,
   egress and logs against the previous version. Missing projection or runtime
   capability is unsupported coverage, not evidence of a network failure.
4. A human performing the approved acceptance check must verify that ordinary
   non-elevated logs succeed and that an actual no-op exec request through the
   same gateway is denied, for example:
   `kubectl --context tuist-k8s-production -n kura exec <selected-pod> -c kura -- /bin/true`.
   Record an explicit Forbidden response naming `pods/exec` and the denied
   identity. Executable-not-found or transport failure is not proof of denial.
   Do not substitute `auth can-i`: that path is not a reliable oracle for the
   gateway's actual request identity. This future human check was not run here.
5. After separate rollout approval, select one affected instance and a control
   on an unaffected node, with a short absolute deadline. Keep private names in
   the existing Secret, not public inline values. The controller patches only
   equipped live Pods owned by those instances; it never backfills old Pod specs.
   Verify actual selection propagation before interpreting missing samples.

Old env-controlled runtime processes cannot gain local expiry or restart-free
disablement. The compatible controller preserves their legacy env on unchanged
templates to avoid an unrequested rollout. The new runtime does not honor that
legacy activation path. Upgrade unsupported pods only through the ordinary
approved runtime rollout; report their coverage gap explicitly.

After an approved production rollout, logs for a selected instance are read with:

```sh
kubectl --context tuist-k8s-production -n kura logs <selected-pod> -c kura --since=10m --timestamps
```

Filter the `event.name` fields `kura.connectivity.sample` and
`kura.connectivity.resolver` in the existing log tooling. A short time window may
omit the startup resolver record; inspect earlier retained logs. Rotation can
remove that record without implying DNS failure. Following logs waits for the
next scheduled cycle and does not initiate network activity.

Disable by clearing selection or expiry through reviewed controller configuration.
Reconciliation removes only the live-Pod annotation; kubelet then refreshes the
file. Local expiry remains the fallback when removal cannot propagate. Retain the
inert projection even with `prepare: false`. **Never roll the controller below
the recorded compatibility floor after adoption**: an older controller rebuilds
templates without the projection and can roll workloads. Removing the projection
requires a separate ordinary runtime rollout. No RBAC, token-mount, database or
stored-data migration needs undoing.

## Capture the next recurrence with view access

Use `infra/mise/tasks/k8s/capture-connectivity.sh` after recording the recurrence's
UTC start time. It requires Bash, jq, kubectl and GNU coreutils `timeout`
(`gtimeout` on macOS). Pass one to four exact Pod names, including a control,
and an existing private parent directory:

```sh
infra/mise/tasks/k8s/capture-connectivity.sh \
  tuist-k8s-production kura <since-UTC> <private-parent> <affected-pod> <control-pod>
```

The script uses only `get` and bounded `logs` requests through the existing
context. It does not exec, debug, proxy, read Secrets or invoke BPF tooling.
Never substitute `cilium-dbg bpf metrics list`: that command can replace the
pinned metrics map on the deployed Cilium version. No credential fallback is
permitted if view access fails.

The whole capture is limited to 120 seconds (three-second kill grace), with
12-second per-request limits (two-second kill grace), eight-second API request
timeouts, 1 MiB API input caps and 256 KiB/2,000-line log input caps. Each projected
output is capped at 1 MiB. The private output directory starts with an `INCOMPLETE`
marker, removed only on successful reads. Timeouts, parsing failures, missing or
ambiguous same-node agents and missing permissions leave incomplete evidence;
absence of matching log records never proves the path was healthy.

Persisted fields are allowlisted: Pod placement/UID/image/restarts/readiness,
StatefulSet rollout revisions, Node conditions, same-node Cilium identity,
fixed-target diagnostic timings, exporter failure categories and classified
Cilium API-timeout timestamps. Raw API specs, env, annotations, log bodies and
error strings are not retained. Names/UIDs still identify workloads, so **these
captures remain private and must never be committed or attached to a public PR**.
This is a bounded, non-atomic observation, not a packet capture or an automatic
fix. Correlation with Cilium API timeouts does not distinguish a host/provider
fault from a Cilium datapath fault; preserve that uncertainty when escalating.
