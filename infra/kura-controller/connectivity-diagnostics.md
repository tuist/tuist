# Connectivity diagnostics through read-only pod logs

Optional Kura telemetry publishes resolver configuration and bounded DNS/TCP/HTTP
header timings from selected instances. Operators read the existing `kura`
container logs through their existing `pods/log` permission. The controller adds
only `KURA_CONNECTIVITY_PROFILE` to the runtime container; there is no diagnostic
sidecar, listener, service account, RBAC change, or gateway bypass. Defaults and
all managed environment overlays leave instance selection empty.

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

The server route maps GET `/ready` to `TuistWeb.PageController.ready/2`, which
returns an empty HTTP 200. Every cycle compares the normal name and the
trailing-dot absolute name, each with one- and three-second combined DNS/TCP
budgets. No configurable URL, path, method, header, command, timeout, or frequency
is accepted. New destinations require a reviewed code change.

## Lifecycle and resource bounds

A regular sidecar was rejected because its crash or image-pull failure makes the
whole Pod NotReady, removing an otherwise healthy Kura replica from Service
endpoints. The implementation instead starts an optional worker before Kura's
bootstrap, on a dedicated OS thread with its own current-thread Tokio runtime.
It receives only the fixed profile, with no application state, readiness handle,
store, or authenticated client. Application startup does not await a sample or
propagate diagnostic errors. Unwinding worker panics are caught. Missing/invalid
profiles and thread creation failure skip the worker; runtime creation failure
stops only diagnostics. There is no additional image to pull or container whose
status can affect Kubernetes readiness.

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

- Four serial samples, followed by a 60-second pause; no concurrent samples or
  catch-up bursts. Each sample has a five-second overall deadline.
- One system-resolver lookup and at most one TCP dial per sample. At most 16
  answers are accepted. Every answer must be an RFC1918 IPv4 or IPv6 unique-local
  address on port 80; IPv4-mapped addresses are checked as IPv4. Loopback,
  link-local/metadata, public, unspecified, multicast, and scoped IPv6 answers
  fail closed, including mixed safe/unsafe answer sets. The first validated
  address is dialed directly, without another lookup or fallback.
- Fixed unauthenticated HTTP/1 GET, including the original trailing dot in Host.
  No proxy handling, redirects, cookies, compression, connection reuse, or auth
  headers. A fixed 8 KiB buffer caps all response bytes read, with at most 64
  parsed headers. The first complete header block ends the sample. Bodies are
  neither drained nor parsed; any prefetched body bytes are discarded. An
  informational response is recorded and closed without looping over more 1xx
  responses. Response headers, bodies, and remote error strings are never logged.
- `/etc/resolv.conf` is the only diagnostic file read, capped at 4 KiB. Its content
  is emitted at startup and on content/readability changes, not every cycle.
- One worker thread and at most one blocking DNS worker, with no new persistent
  storage. Diagnostic CPU is part of the existing Kura container's real resource
  consumption. Autosizing excludes other containers; it cannot separate this
  built-in telemetry from other Kura work.

## Read-only access boundary and tradeoffs

The Pomerium, kube-impersonator, and tuist-ops authorization path remains intact.
No exec, attach, port-forward, pod/service/node proxy, ephemeral-container, or
Secret access is added. Reading/following logs cannot trigger requests or alter
frequency. Deployment configuration selects exact KuraInstance names within the
controller's watched namespace; wildcard/prefix selection is unsupported. The
reserved profile environment variable is stripped from instance `ExtraEnv`, so
an instance-level override cannot bypass the deployment allowlist. Only trusted
runtime/deployment changes can extend the fixed request profile.

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
readiness. Stage errors are fixed strings. Each sample includes target, start
time, budget and, when available, HTTP status.

## Rollout, acceptance, and rollback

This PR does not deploy or enable diagnostics. Use the normal reviewed deployment
process; no incident elevation is required to implement or read these logs.

1. Build/publish the updated Kura runtime and controller with their existing
   workflows. Keep selection empty while upgrading. An older runtime ignores
   the new variable and emits no diagnostic records; verify the selected image
   contains this module before treating absent logs as a network failure.
2. In an approved non-production environment, configure exact instance names in
   `kuraController.connectivityDiagnostics.instances`, using KuraInstance names
   rather than ordinal pod names. The controller uses
   `telemetry.deploymentEnvironment` to choose the matching compiled profile and
   rejects selection without a watched namespace or valid environment.
3. Inspect the rendered and admitted Pod spec: one additional fixed-profile
   environment variable on `kura`, with unchanged containers, probes, mounts,
   resources and service-account settings. Observe the normal StatefulSet rollout
   and readiness. Adding/removing the environment variable changes the template;
   an `OnDelete` StatefulSet requires its existing controlled replacement process.
4. A human performing the approved acceptance check must verify that ordinary
   non-elevated logs succeed and that an actual no-op exec request through the
   same gateway is denied, for example:
   `kubectl --context tuist-k8s-production -n kura exec <selected-pod> -c kura -- /bin/true`.
   Record an explicit Forbidden response naming `pods/exec` and the denied
   identity. Executable-not-found or transport failure is not proof of denial.
   Do not substitute `auth can-i`: that path is not a reliable oracle for the
   gateway's actual request identity. This future human check was not run here.
5. Compare normal/absolute-name samples, CPU, memory, and log volume. Test loss of
   the target endpoint without a loss of Kura readiness before expanding selection.

After an approved production rollout, logs for a selected instance are read with:

```sh
kubectl --context tuist-k8s-production -n kura logs <selected-pod> -c kura --since=10m --timestamps
```

Filter the `event.name` fields `kura.connectivity.sample` and
`kura.connectivity.resolver` in the existing log tooling. A short time window may
omit the startup resolver record; inspect earlier retained logs. Rotation can
remove that record without implying DNS failure. Following logs waits for the
next scheduled cycle and does not initiate network activity.

Rollback removes selected names from the reviewed values and deploys the
controller configuration. Reconciliation removes the profile environment variable
and selected pods follow their normal replacement procedure. No RBAC, token-mount,
database, or stored-data migration needs undoing. Service-account-token hardening
is independent of diagnostics and remains separate fleet-wide work.
