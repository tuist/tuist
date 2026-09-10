# Connectivity diagnostics through read-only pod logs

The optional `connectivity-probe` container publishes resolver configuration and
bounded DNS/TCP/HTTP timings from a selected Kura instance's pods. Operators use
the existing `pods/log` read permission; there is no new API or permission tier.
It is disabled by default, including all managed environment overlays.

## Motivation and scope

During the South America connectivity investigation, the normal production
identity could get pods and logs but could not execute `cat /etc/resolv.conf` or
an unauthenticated `curl` against the internal server's `/ready` endpoint.
Human-approved diagnostics subsequently measured about 0.91 seconds for DNS and
about 1.14 seconds cumulatively through TCP setup in both affected replicas.
The one-second connect budget failed while three seconds succeeded. An absolute
DNS name also succeeded within one second. That timeout fix is PR #13112;
this feature changes neither Kura's client timeout nor its readiness behavior.

The profile specifically diagnoses the managed control-plane Service
`tuist-tuist-server.tuist.svc.cluster.local:80/ready`. It compares the normal and
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
- The probe has no listener and accepts no CLI arguments or environment config.
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
  a small steady cost. Start with a small instance set.
- The Go resolver reads the same kubelet-provided resolver file, but its search,
  retry, address ordering and timing behavior need not match libc/curl or Kura's
  Rust client exactly. First-address-only dialing also omits Happy Eyeballs and
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

No cluster operations are part of this implementation task. A later approved
rollout should:

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
4. Verify with a normal, non-elevated production session that logs work and
   `kubectl auth can-i create pods/exec -n kura` remains `no`. Do not use a live
   elevated identity as proof of the read-only authorization boundary.
5. Compare the normal/absolute-name timing samples, check CPU/memory/log volume,
   and expand the reviewed selection only if useful.

After that rollout, the following are sufficient and do not need JIT:

```sh
kubectl --context tuist-k8s-production -n kura logs kura-pedidosya-sa-west-1-0 -c connectivity-probe --since=10m --timestamps
kubectl --context tuist-k8s-production -n kura logs kura-pedidosya-sa-west-1-1 -c connectivity-probe --since=10m --timestamps
```

An absent container means the capability has not rolled out to that pod; it is
not a reason to request broader access automatically. The last resolver record
and four subsequent sample records form one profile run. `--follow` waits for
the next scheduled sample without triggering network requests.

Rollback: remove the instance names from the reviewed values and deploy the
controller configuration through the normal process. Reconciliation removes the
sidecar and restores the prior token-automount setting in the desired template;
the selected pods roll again. No RBAC, database, or data migration needs undoing.
