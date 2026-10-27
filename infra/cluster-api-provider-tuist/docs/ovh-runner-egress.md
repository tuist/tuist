# OVH Linux runner egress

`capi.ovhRunnerEgress` routes runner jobs through one OVH Additional IP block
per environment. All three blocks are delivered and attached to the vRacks
below. Staging's move to its existing cache vRack was confirmed through the OVH
API on 2026-10-26; canary and production were confirmed in OVH Manager screenshots.
Checked-in activation remains **disabled in every environment**. Staging's
bounded qualification exercised activation, rollback, repair and reboot together
with real private-cache transfers; evidence and remaining rollout limits are
below. No public allowlist documentation changes until production has passed
the checks below.

| Environment | Attached vRack | Delivered block | Usable addresses | Gateway |
| --- | --- | --- | --- | --- |
| staging | pn-2023588 | 5.39.98.144/29 | 5.39.98.145–5.39.98.149 (5) | 5.39.98.150 |
| canary | pn-2025491 | 5.196.103.232/29 | 5.196.103.233–5.196.103.237 (5) | 5.196.103.238 |
| production | pn-2025483 | 5.135.7.160/27 | 5.135.7.161–5.135.7.189 (29) | 5.135.7.190 |

OVH reserves the first, penultimate and last addresses for network, gateway and
broadcast. A block has a 5 Gbps limit; each RISE private NIC has its own limit.
See [OVH's Additional IP guide](https://support.us.ovhcloud.com/hc/en-us/articles/4403594838803-Configuring-an-Additional-IP-block-in-a-vRack).
The controller accepts canonical public IPv4 /24 through /29 blocks. It does
not order addresses or attach the block itself; those are prerequisites.

## Controller lifecycle

The provider receives `--ovh-runner-egress-config` and reads the ConfigMap in
its secrets namespace. Disabled configurations without reservations make no
OVH, SSH or Cilium API calls. Cache Machines are excluded from enrollment.

For a Ready Kata Machine, the controller:

1. Validates the block, existing private-network annotation, Machine vRack and
   Node identity. Allocates one address by Machine UID and OVH service in a
   separate, controller-owned `-reservations` ConfigMap. Resource-version
   conflicts stop the operation before any host configuration.
2. Calls `EnsureVRack`, which refuses to move a NIC from another vRack. Waits
   for a read confirming attachment. Persists the private NIC MAC before SSH,
   so an interrupted configuration still has durable cleanup intent.
3. Installs the address as a /32 on the MAC-selected private NIC, source rule
   priority 10430 and routing table 243. Only traffic sourced from that address
   uses the block's gateway. The primary public IP and main default route stay
   in place. Foreign routes, a conflicting rule, a changed address or the
   primary default-route NIC cause an error rather than being overwritten.
4. Installs `tuist-runner-egress.service` before kubelet and a 60-second repair
   timer. The host uses loose reverse-path filtering on the private NIC.
   Script hash plus Node BootID triggers the controller's SSH repair after an
   update or reboot. The existing pinned SSH fingerprint is mandatory.
5. Creates `ovh-runner-<machine UID>`, a cluster-scoped
   `CiliumEgressGatewayPolicy`. It selects only `tuist.dev/runner=true` pods in
   `tuist-runners` on that host and uses the same host as gateway. RFC1918,
   CGNAT and IPv4 link-local ranges are excluded. The existing runner
   NetworkPolicy still owns access restrictions; gateway exclusions do not
   grant access to private destinations.
6. Records the address and revision on the Node and marks
   `RunnerEgressReady=True`. This means configuration was applied, **not** that
   a real job has passed the public egress probe. The provider refreshes the
   policy annotation after reboot so Cilium reselects the configured interface.

The policy uses explicit ownership annotations rather than an invalid
namespaced-Machine owner reference on a cluster-scoped resource. Every
reconcile repairs missing or altered policy specs and refuses unowned objects.
Cilium 1.18.7 supports the paired pod/node selectors, local gateways and a
source-address FIB lookup without `BPF_FIB_LOOKUP_DIRECT`; see its
[policy API](https://github.com/cilium/cilium/blob/v1.18.7/pkg/k8s/apis/cilium.io/v2/cegp_types.go),
[egress datapath](https://github.com/cilium/cilium/blob/v1.18.7/bpf/lib/egress_gateway.h)
and [FIB helper](https://github.com/cilium/cilium/blob/v1.18.7/bpf/lib/fib.h).
Physical routing and device selection were qualified on the staging host below;
each additional target host still requires validation.

## Staging findings on 2026-10-26

The remaining staging runner is
`tuist-tuist-ovh-fleet-runners-linux-h72m4-llfpg`, service
`ns3066567.ip-193-70-46.eu`, kernel 6.8.0-139. Its Machine and Node use cache
vRack `pn-2023588`, with retained private reservation `172.30.241.4`. This is
an intentional private cache connection. The separate private-cache rollout
retired the legacy RISE-S host after preserving its fixtures.

The runner's Cilium 1.18.7 reports both `enp6s0` (public) and `enp7s0`
(private, `172.30.241.4`) as managed devices. BPF masquerading and egress
Gateway are enabled cluster-wide. This is evidence about that host only.

**The staging attachment conflict is resolved by sharing the cache vRack.**
The operator moved the unused `5.39.98.144/29` block from `pn-2025489` to
`pn-2023588`. A subsequent API read confirms its gateway `5.39.98.150/32`,
region `eu-west-gra`, and `PUBLIC-ROUTING-1-AZ` routing type on the destination;
the source vRack has no IP blocks. OVH still lists the runner on `pn-2023588`.
The block move did not change the runner NIC, private reservation or host route.
The original separate-vRack plan is superseded for staging only.

The private-cache provider changes are integrated: explicit Kata `vRackID`
enrollment participates in private address allocation and reciprocal peer-route
reconciliation. Egress rollback preserves that enrollment and its reservation.
This does not include the separate application-side cache cohort migration.

Staging's provider-only deployment preserves its concurrent Kura LVM changes.
The integration branch `codex/ovh-runner-egress-staging` combines the live
provider baseline with this PR; image `7f4abb31` was deployed by
[run 40410535415](https://github.com/tuist/tuist/actions/runs/40410535415).
The guarded workflow requires the exact previous live image, applies only the
egress ConfigMap/RBAC and updates the provider image/argument. It shares the
normal staging deployment concurrency lane and does not upgrade the application
or cache releases. Do not deploy an older provider over the retained changes.

Canary and production still need their intended private-cache enrollment
reconciled with the recorded public block attachments before enabling either
environment.

### Qualification evidence

- Baseline [run 40408723993](https://github.com/tuist/tuist/actions/runs/40408723993)
  verified primary egress `193.70.46.18` and a real remote Gradle cache round trip.
- Enabled [run 40411992271](https://github.com/tuist/tuist/actions/runs/40411992271)
  verified `5.39.98.145` inside the job container, compiled the real Gradle plugin
  and test sources, then restored both tasks `FROM-CACHE` with matching class
  checksums. The dispatched cache endpoint was
  `http://kura-tuist-ovh-gra-runners.kura.svc.cluster.local:4000`.
- The live Cilium BPF map selected `5.39.98.145` and the local gateway for runner
  source IPs, with the intended private-range exclusions. Probes from a Kata
  runner timed out against the cluster API and private-host SSH address.
- Host source routing used table 243 through `5.39.98.150` on `enp7s0`, while
  ordinary host traffic retained `193.70.46.18` and the cache route retained
  `via 172.30.241.2`. Removing only the owned table-243 default on a drained
  host at 22:25:16 UTC was repaired automatically at 22:25:53 UTC; a subsequent
  public-IP probe passed.

The first disable drill found a systemd cleanup bug: explicitly stopping the
egress oneshot propagated through kubelet's loaded `Requires` dependency and
stopped kubelet, even though the oneshot was inactive. The host was drained;
no runner jobs were interrupted. Public state was removed and its reservation
released, and private state remained intact. Kubelet was restored through
host-key-pinned SSH. Cleanup now removes the kubelet drop-in and reloads systemd
**before** stopping the egress service. The host-script regression models the
loaded dependency and fails with the original order, including the failed
cleanup path that retains address ownership.

The corrected provider image is `40304e0d`, built and tested by
[run 40412827850](https://github.com/tuist/tuist/actions/runs/40412827850).
That run's deployment guard stopped after a concurrent staging release restored
the prior `3e8f2a29` provider. Once that release finished, the corrected image
was applied through a resource-version-guarded Deployment patch after verifying
that `3e8f2a29` is an ancestor of the integration build and that egress remained
disabled with no reservations. All existing arguments were preserved.

The repeated enable/disable drill on `40304e0d` removed the public address,
routes, condition and reservation while kubelet retained PID `538232` and the
private address/route/timer remained intact. Disabled
[run 40412838281](https://github.com/tuist/tuist/actions/runs/40412838281)
also verified primary-IP egress and a private-cache upload followed by a remote
`cacheProbe FROM-CACHE` result (after restoring kubelet from the first drill).

The approved drained reboot changed BootID from
`f75e2b9b-1ae5-422f-8362-c18f9884ee35` to
`c1f02a5d-b3b1-47ab-8ac0-8a3b64fabaf3`. On the new boot, egress configuration
finished at monotonic 17.904 seconds and kubelet started at 18.293 seconds.
Both addresses, table 243, the source rule and the private-cache route returned.
[Post-reboot run 40415653210](https://github.com/tuist/tuist/actions/runs/40415653210)
verified `5.39.98.145` and repeated the real Kotlin compilation/remote restore
with matching class checksums. Cilium's post-boot map again selected the public
address for runner sources.

**Recovery-time limitation:** the reboot window lasted roughly ten minutes
(22:40–22:50 UTC), and OVH recorded a server-down monitoring intervention.
The previous shutdown log contains busy kubelet mounts before journald stops;
it does not establish the cause of the remaining delay. The host returned with
kernel `6.8.0-147` instead of `6.8.0-139`; this task did not install that upgrade.
No second reboot, boot-mode change or reinstall was issued. Persistence passed,
but this is not evidence of fast host recovery. Investigate the delay before
treating host replacement/recovery time as qualified.

Machine deletion/reinstall and address reuse by a replacement were not tested
on the sole staging runner. Bandwidth alerts remain definitions only. These
gates, plus canary/production private-vRack alignment, remain before promotion.

### Staging state after qualification on 2026-10-26

The final combined provider is `c1e502d4`, published by
[run 40415854542](https://github.com/tuist/tuist/actions/runs/40415854542).
It also preserves the rack-install fixes from the concurrent `ae6b8b3d` release,
which replaced the provider during the reboot window. After that rollout
finished, a resource-version-guarded patch restored the integrated controller;
both private and public network revision annotations converged on the new BootID.

Egress was then disabled to match the checked-in configuration. Its reservation
map is empty; the public /32, table 243, rule 10430, egress timer and kubelet
dependency were removed while kubelet retained post-boot PID `1487`. The private
reservation `172.30.241.4`, route through `172.30.241.2` and private repair timer
remain. The temporary privileged pod and qualification annotation were removed,
and the node was uncordoned. Keep the provider's cleanup capability installed
through any future activation; do not let an older parallel deployment replace
it while an allocation exists.

[Final disabled-state run 40416946444](https://github.com/tuist/tuist/actions/runs/40416946444)
passed the exact primary-IP assertion and another real private-cache upload and
remote hit after cleanup on the final combined provider.

### PR deployment recheck on 2026-10-27

Staging had advanced to provider `a59b98c6`, including Kura storage and nested-KVM
rehearsals. The provider-only integration build `e8dcb75e` preserves that baseline
and contains the PR's identical egress implementation and regression tests.
It is not a full deployment of the PR checkout. The guarded
[build and deployment](https://github.com/tuist/tuist/actions/runs/40492616173)
passed all CI gates and replaced only the provider and egress configuration/RBAC,
with egress initially disabled. Application and cache releases were not upgraded.

The first baseline job stopped before compilation because the fixture accepted
only regional EU-West cache names, while staging still dispatches its existing
`kura-tuist-ovh-gra-runners` endpoint. The PR now accepts that exact endpoint in
addition to the regional names, retains the staging URL guard, and reports an
explicit scope error. Shellcheck and accepted/rejected endpoint checks passed.

- [Corrected baseline](https://github.com/tuist/tuist/actions/runs/40493029798)
  passed exact primary IP `193.70.46.18`, fresh production/test Kotlin compilation,
  uploads and remote restores with matching class checksums.
- [Enabled job](https://github.com/tuist/tuist/actions/runs/40493880351)
  passed exact public IP `5.39.98.145` and the same real private-cache checks.
  Both network conditions were True, their revisions matched the current BootID,
  and the existing KVM readiness condition remained True.
- [Final disabled-state job](https://github.com/tuist/tuist/actions/runs/40494320217)
  passed exact primary IP `193.70.46.18` and both Kotlin remote restores with
  matching checksums after cleanup on provider `e8dcb75e`.

Activation and rollback waited for zero nonterminal runner pods on the cordoned
host. Cleanup emptied the public reservation map and removed the egress condition
and Node annotations while private-network readiness and Node readiness remained
True. The temporary qualification annotation was removed and scheduling resumed.
No host reboot, Machine replacement or direct host diagnostics were repeated.
The human Kubernetes identity could not read the cluster-scoped Cilium policy;
this recheck uses controller convergence and real job results, not a fresh BPF
map inspection. The earlier recovery-time and promotion limitations still apply.

## Qualification and rollout

1. Recheck the recorded block/vRack associations before activation; delivery
   and attachment are confirmed above. Preserve staging's shared cache vRack.
   Confirm enough
   usable addresses for hosts plus replacement surge; retained failed-cleanup
   reservations consume capacity.
2. Deploy the provider and charts with egress disabled and the recorded CIDRs.
   After integrating the private-cache provider changes, enable only staging. Read
   `RunnerEgressReady` and both Node
   annotations. A partial fleet rollout leaves unconfigured hosts on their
   primary public IP; do not promise the new allowlist yet.
   The chart adds an operator flag, so use the matching provider release. For
   pre-release staging checks, prefer the guarded provider-image workflow's
   `deploy_staging` option with `expected_staging_image`; it requires disabled
   egress and empty reservations. Only use a full application deployment from
   a branch that contains the current staging changes, with its matching
   `capi_image_tag`. An older image will reject the egress flag or stop owning
   existing state if the flag is removed with it.
3. For **each** staging host, verify the private NIC appears in `cilium-dbg
   status --verbose`, including masquerading devices. A newly addressed NIC
   should be auto-detected; if it is not, qualify an explicit Cilium device
   configuration before promotion. Do not change devices cluster-wide on an
   assumption. Inspect `cilium-dbg bpf egress list` for the runner source IP,
   matching host gateway and allocated egress address.
4. On the host, inspect `ip -4 rule show priority 10430`, `ip -4 route show
   table 243`, and `ip -4 route get 1.1.1.1 from <allocated-address>`. Confirm
   the existing primary route still serves host traffic.
5. Run real Kata jobs on every staging host that print
   `curl -fsS https://api.ipify.org`; require the exact reserved address.
   Exercise DNS, image pulls and both job/dind traffic. Confirm private-range
   access remains denied except for the existing explicit NetworkPolicy
   allowances. Confirm cache/private paths and ordinary host connectivity.
6. Remove an owned route to exercise the repair timer, then reboot a drained
   staging host. Verify the address is restored before kubelet, the revision
   includes the new BootID, and a fresh job still uses the block. Exercise
   disable/re-enable and a drained Machine deletion. Confirm policy, host
   state and reservation cleanup, then safe reuse by a replacement.
7. Provision and verify the bandwidth alerts below. Roll out canary, run the
   runner acceptance gate, then production. Canary/production writes require
   the normal human elevation or deployment workflow.
8. Only after production jobs pass, replace the Linux /32 table and maintainer
   comment in `server/priv/docs/en/guides/server/network.md` with the delivered
   production /27. Keep the macOS range `95.130.119.0/24`.

## Rollback and deletion

Set `capi.ovhRunnerEgress.enabled=false` while keeping the provider, ConfigMap
and RBAC deployed. Wait until all runner `RunnerEgressReady` conditions, Node
annotations and owned Cilium policies are gone and the reservation map is
empty. Then an older provider image or chart may be deployed. Changing the
allocated CIDR or vRack while reservations exist is rejected.

Machine deletion first uses the existing running-job drain barrier. Cleanup
withdraws the Cilium policy and confirms it is absent on a subsequent read,
then stops the host repair timer/service and removes its rule, routes, address
and kubelet dependency. Only successful host cleanup frees the reservation;
only afterwards does deletion drop SSH credentials and request the normal
asynchronous OS reinstall. Disabling the feature follows the same cleanup.
It returns job egress to the primary IPs, so coordinate allowlist changes.

An unreachable host retains its address and blocks the Machine finalizer.
Never delete its reservation just because the Machine is absent or reinstall
was accepted: the old OS may still own the IP. Restore access, or obtain
independent proof of wipe/network isolation before a reviewed manual recovery.
Forced finalizer removal leaves retained reservations intentionally.

## Bandwidth monitoring

The provider exports `capt_runner_egress_info{node,mac,vrack,cidr}` after
configuration, refreshes it after restart and removes it after cleanup.
The monitoring chart retains `node_network_info`, allowing a MAC join with
per-device transmit/receive byte counters. This avoids assuming NIC names or
counting primary-public traffic toward the private block limit.

`infra/helm/k8s-monitoring/ovh-runner-egress-alert-rules.json` contains two
Grafana provisioning API rules for sustained transmit and receive traffic
above 80% of 5 Gbps for ten minutes. They are **definitions, not live alerts**.
Provision them into the existing Alerts folder's `Runner networking` group
with a one-minute interval, preserving the notification routing tree. Confirm
`affected_service=Runners` reaches the intended existing receiver. No-data is
normal while disabled; verify data is present on every configured host before
calling monitoring operational. Evaluate per-host NIC saturation separately
against its contracted rate, typically 1 Gbps for the RISE private NIC.

Run `bash infra/helm/k8s-monitoring/test-ovh-runner-egress-alert.sh` with jq and
promtool. It checks the real shipped expressions with multiple hosts,
public-interface exclusion, environment isolation and the pending period.

## Local validation

Run the provider's Go tests with Bash 4+ on PATH and
`TUIST_TEST_HELM` pointing at Helm. The runner tests cover address bounds and
exhaustion, idempotence, rejected network/service changes, disabled/cache
isolation, attachment and SSH failure, ownership, reboot refresh, reservation
write failure, rollback retention and managed chart rendering. Shellcheck the
host script and alert test. These checks do not replace the live staging
qualification above.
