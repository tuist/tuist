# Connectivity diagnostics through read-only pod logs

The optional `connectivity-probe` container publishes resolver configuration and
bounded DNS/TCP/HTTP timings from a selected Kura instance's pods. Operators use
the existing `pods/log` read permission; there is no new API or permission tier.
It is disabled by default, including all managed environment overlays.

## Blocking lifecycle issue — do not enable

The current regular sidecar contributes to the Pod Ready condition. An image-pull
failure or crash can remove a healthy Kura replica from Service endpoints; a
shared failure across replicas can remove all ready backends. This is a merge
and rollout blocker, not an accepted operational tradeoff. Native restartable
init sidecars do not fix it: Kubernetes includes them in
[ContainersReady](https://github.com/kubernetes/kubernetes/blob/v1.34.0/pkg/kubelet/status/generate.go).
A lifecycle-independent design remains required before enabling this feature.
The corrections below do not resolve this blocker.

## Motivation and scope

During the South America connectivity investigation, the normal production
identity could get pods and logs but could not execute `cat /etc/resolv.conf` or
an unauthenticated `curl` against the internal server's `/ready` endpoint.
Human-approved diagnostics subsequently measured about 0.91 seconds for DNS and
about 1.14 seconds cumulatively through TCP setup in both affected replicas.
The one-second connect budget failed while three seconds succeeded. An absolute
DNS name also succeeded within one second. That timeout fix is PR #13112;
this feature does not change Kura's client timeout or application readiness handler.
The sidecar does affect Kubernetes Pod readiness, as described above.

The profile specifically diagnoses the managed control-plane Service
`tuist-tuist-server.<namespace>.svc.cluster.local:80/ready`. The only accepted
profiles are `production` (`tuist`), `staging` (`tuist-staging`), and `canary`
(`tuist-canary`). The controller passes its deployment environment as the single
argument; any other profile is rejected. It compares the normal and
trailing-dot absolute name with one- and three-second combined DNS/TCP budgets.
The existing server route maps GET `/ready` to `TuistWeb.PageController.ready/2`,
which returns an empty HTTP 200 response without a state-changing operation.
It intentionally does not accept arbitrary hosts, IPs, paths, headers, methods,
timeouts, commands, or repeat counts. Other destinations need a reviewed code
change establishing that their unauthenticated GET is safe and necessary.

## Security boundary

The threat is a read-only operator or agent with a valid Pomerium session using
diagnostics to gain execution, credentials, a request proxy, or workload writes.
RBAC grants verbs on resources/subresources, not a safe command language:
`pods/exec` is arbitrary execution even when the intended command is a read.
Restricting it to named pods still exposes their mounted secrets and writable
state. See Kubernetes' [RBAC reference](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
and [privilege escalation guidance](https://kubernetes.io/docs/concepts/security/rbac-good-practices/).

- `infra/helm/pomerium/templates/access-tiers.yaml` remains unchanged. The normal
  `tuist-admins` and `tuist-eng` identities still receive `view`; no exec, attach,
  port-forward, pod/service/node proxy, ephemeral-container, or Secret access is
  added.
- Pomerium, `kube-impersonator`, and tuist-ops still authenticate and resolve every
  production kubectl request as before. There is no diagnostic bypass, new
  service account, delegated exec broker, or elevation path. Logs remain subject
  to Kubernetes RBAC and the existing gateway access audit trail.
- The probe has no listener or environment config. Its sole argument selects one
  of the three fixed environment profiles; no arbitrary destination is accepted.
  Reading or following logs cannot trigger probes or increase their frequency.
  A read-only user cannot select new network targets by changing pod metadata.
- Controller deployment configuration selects exact instance names, not a
  wildcard or user-writable annotation. The controller adds the sidecar to every
  replica of only those instances. No managed instance is opted in by this PR.
- The sidecar receives no environment, Secret, data, host, or shared filesystem
  mounts. It reads only its fixed `/etc/resolv.conf` path (capped at 4 KiB).
  The selected pod has service-account-token automount disabled, including for
  Kura, which does not use the Kubernetes API. It has separate process/root
  filesystem isolation and no process-namespace sharing. Admission webhooks
  that inject credentials would invalidate this assumption and must be checked
  at rollout.
- The container runs as UID/GID 65532, with a read-only root filesystem, no Linux
  capabilities, no privilege escalation, and RuntimeDefault seccomp. Requests
  reserve 5m CPU / 16 MiB; limits are 50m CPU / 32 MiB.
- Each sample uses a fresh connection, one DNS lookup operation, and at most one
  TCP connection attempt. DNS retries/search expansions inside that lookup are
  bounded by the shared connect deadline. All returned addresses must be private
  and unzoned; loopback, link-local/metadata, public, unspecified and multicast
  addresses fail closed. The first validated address is dialed directly, without
  a second lookup. At most 16 answers are accepted.
- Requests use fixed unauthenticated HTTP GETs. Proxy environment variables,
  redirects, cookies, compression, and connection reuse are disabled. Response
  headers are capped at 8 KiB; at most 4097 body bytes are read to detect a 4 KiB
  limit, then discarded. No body, response header, or remote error text is logged.
  Every sample has a five-second overall deadline, including body reads.
- Four serial samples run at startup and then after a 60-second pause following
  completion. There is no concurrent probing or catch-up burst. Restarting a
  pod can trigger startup samples, but the read-only role cannot restart it.

The approved Service is intentionally private: banning all private destinations
would remove the diagnostic being requested. DNS compromise could redirect the
fixed unauthenticated `/ready` GET to another private address; validation is not
an attestation of Service ownership. There are no credentials or user-controlled
payloads to forward, and callers cannot exploit it as a general request proxy.
The existing pod network policies still govern all traffic. A compromised probe
binary or mutating deployment identity is outside the read-only-caller threat
model; container isolation alone is not a network sandbox for malicious code.

## Why this design

[Containers in a pod share its network namespace](https://kubernetes.io/docs/concepts/workloads/pods/),
so a sidecar sees the same pod routing, DNS policy, source address, and Cilium
egress shaping as Kura. A diagnostic Job or node-level probe would not necessarily
exercise those paths. A privileged agent that enters network namespaces would
create a much broader host trust boundary. An on-demand gateway broker would
need privileged execution or an authenticated pod endpoint, command validation,
rate limits, and another authorization path. Periodic fixed samples through
already authorized logs avoid that machinery and let an unavailable control
plane or unready Kura process be diagnosed independently.

Costs and limitations:

- This is a maintained sample stream, not on-demand arbitrary troubleshooting.
  Only opted-in, controller-managed Kura workloads are supported. Selection is
  per instance; operators select an individual replica by reading its logs.
- Installing, updating, or removing the sidecar changes the StatefulSet template
  and normally rolls the selected pods. It cannot inspect an existing pod until
  the approved rollout has replaced it. An `OnDelete` StatefulSet needs its
  existing controlled replacement procedure. No agent should bypass that gate.
- A missing/broken sidecar image or repeated sidecar crashes can prevent overall
  pod readiness; probe target failure only emits a result and never exits the
  sidecar. Resource reservations and up to four GETs per minute per replica add
  a small steady cost. Do not enable until the lifecycle blocker is resolved.
- CPU autosizing reads only the `kura` container. Missing Kura usage is omitted,
  not recorded as zero; sidecar CPU cannot inflate Kura's historical sizing signal.
- The Go resolver reads the same kubelet-provided resolver file, but its search,
  retry, address ordering and timing behavior need not match libc/curl or Kura's
  Rust client exactly. `StrictErrors` is left at its default false; temporary
  search-query errors do not deliberately abort the remaining search-list walk.
  First-address-only dialing also omits Happy Eyeballs and
  fallback addresses. These results diagnose the network path, not application
  client equivalence. Container-specific resolver-file edits are not observed.
- Timings are cumulative milliseconds from request start: `dns_ms`, `connect_ms`,
  `first_byte_ms`, and `total_ms`. Missing stages did not finish successfully.
  `connect_ms - dns_ms` estimates TCP time; `total_ms` includes reading/discarding
  the bounded body. Statuses such as 302 or 503 remain useful HTTP results even
  with `outcome: ok`; that outcome means transport completed, not readiness.
- The profile is HTTP, with no TLS or authenticated endpoint measurement. It does
  not probe direct backend IPs or the local Kura listener. It requires private
  Service addresses and the fixed managed Service name/namespace/port.
- Resolver settings and timings are visible wherever existing pod logs are
  readable/collected. They use existing log retention; there is no new database
  or persistent volume. The gateway audits the log read, not each scheduled GET.

## Rollout and use

No cluster operations are part of this implementation task. The following is a
future acceptance procedure, gated on resolving the lifecycle blocker first:

1. Build/publish the controller image using the existing Kura Controller Image
   workflow. Its multiarchitecture image now contains `/connectivity-probe` as
   well as `/manager`. Keep the chart's controller image tag pinned to that build.
2. Validate first in an approved non-production environment with the matching
   internal Service. In reviewed Helm values, set
   `kuraController.connectivityProbe.instances` to exact KuraInstance names. For
   the motivating production instance the entry would be
   `kura-pedidosya-sa-west-1`; do not use the `-0`/`-1` pod names. Leave all other
   instances unselected. Use the normal deployment process, not incident JIT.
3. Inspect the rendered Pod spec and admission result: no probe mounts/env or
   credential injection, token automount false, correct security/resource limits,
   matching image with the binary, and unchanged Kura container configuration.
   Observe the normal StatefulSet rollout and readiness before proceeding.
4. A human performing the approved acceptance check must use a non-elevated
   production session and verify that logs succeed, then attempt the actual exec
   request through the same gateway:
   `kubectl --context tuist-k8s-production -n kura exec <selected-pod> -c kura -- /bin/true`. Record an explicit Forbidden
   response naming `pods/exec` and the denied identity. An executable-not-found,
   transport failure, or success does not prove this boundary; investigate rather
   than accepting the check. `/bin/true` is a no-op if access is unexpectedly
   granted. Do not use `auth can-i` as the acceptance oracle or use an elevated
   session. This is a future human-run check; it was not executed in this task.
5. Compare the normal/absolute-name timing samples, check CPU/memory/log volume,
   and expand the reviewed selection only if useful.

After that rollout, the following are sufficient and do not need JIT:

```sh
kubectl --context tuist-k8s-production -n kura logs kura-pedidosya-sa-west-1-0 -c connectivity-probe --since=10m --timestamps
kubectl --context tuist-k8s-production -n kura logs kura-pedidosya-sa-west-1-1 -c connectivity-probe --since=10m --timestamps
```

An absent container means the capability has not rolled out to that pod; it is
not a reason to request broader access automatically. Resolver configuration is
emitted on startup and when its contents or readability changes, not every run.
A short `--since` window may omit it: inspect earlier retained container logs for
the last resolver record. After log rotation that record may no longer be retained;
its absence is not a DNS failure. Each run still emits up to four timing records. `--follow` waits for
the next scheduled sample without triggering network requests.

Rollback: remove the instance names from the reviewed values and deploy the
controller configuration through the normal process. Reconciliation removes the
sidecar and restores the prior token-automount setting in the desired template;
the selected pods roll again. No RBAC, database, or data migration needs undoing.

## Token-hardening scope

Token automount remains disabled only for selected pods in this change. Moving
that setting into the unconditional pod template would change every managed Kura
StatefulSet and trigger a fleet-wide rollout despite diagnostics being disabled.
That worthwhile hardening needs a separately reviewed rollout. Removing a sidecar
already changes the pod template; moving the token setting alone does not remove
that rollback rollout. No claim is made that the unselected fleet is hardened.
