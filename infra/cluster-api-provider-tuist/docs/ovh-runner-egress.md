# OVH Linux runner egress

`capi.ovhRunnerEgress` gives Linux runner jobs one OVH Additional IP block per
environment while preserving each host's primary management IP and private-cache
connection. Checked-in values enable **staging and canary**; **production remains
disabled** until its allowlist migration and rollout gates are complete. The
provider configures existing blocks; it does not order them or move a NIC between
vRacks. Public egress alone does not enroll a runner into private-cache routing:
that still requires explicit Machine `spec.vRackID` enrollment.

## Block inventory

Recorded attachments from 2026-10-26; recheck before activation:

| Environment | Attached vRack | Block | Usable host addresses | Gateway |
| --- | --- | --- | --- | --- |
| staging | pn-2023588 | 5.39.98.144/29 | 5.39.98.145–5.39.98.149 | 5.39.98.150 |
| canary | pn-2025491 | 5.196.103.232/29 | 5.196.103.233–5.196.103.237 | 5.196.103.238 |
| production | pn-2025483 | 5.135.7.160/27 | 5.135.7.161–5.135.7.189 | 5.135.7.190 |

Staging's block was moved onto its existing cache vRack, preserving the runner's
private NIC and reservation. Canary and production still need their public-block
attachments aligned with their intended private-cache networks before activation.
Canary's configured target is `pn-2024092`; its block must be moved there before
deploying the enabled overlay. Production's intended private-cache vRack is
`pn-2024093`. Never move an enrolled runner's NIC to resolve this mismatch.

The controller accepts canonical public IPv4 /24 through /29 blocks. OVH reserves
the first, penultimate and last addresses for network, gateway and broadcast.
Allow capacity for host replacement surge and reservations retained after failed
cleanup. See [OVH's Additional IP guide](https://support.us.ovhcloud.com/hc/en-us/articles/4403594838803-Configuring-an-Additional-IP-block-in-a-vRack).

## Controller contract

The provider reads the namespaced ConfigMap selected by
`--ovh-runner-egress-config`. With egress disabled and no reservations, its egress
reconciler makes no OVH, SSH or Cilium calls. Cache Machines are excluded.
Activation applies to eligible Ready Kata Machines across the environment;
there is no per-host activation switch.

For each runner, it reserves an address by Machine UID and OVH service in a
controller-owned `-reservations` ConfigMap. It validates the Machine's vRack and
existing private-network annotation, confirms NIC attachment, and persists the
NIC MAC before SSH so interrupted configuration retains cleanup intent.

The host script selects the private NIC by MAC and installs a public /32,
source rule 10430 and routing table 243 through the block gateway. The primary
IP and main default route remain in place. Foreign routes/rules, unowned
addresses and selection of the primary default-route NIC are rejected.
`tuist-runner-egress.service` runs before kubelet; a 60-second timer repairs
host drift. Pinned SSH reconciliation is keyed by script hash and Node BootID.

An owned `CiliumEgressGatewayPolicy` selects only `tuist.dev/runner=true` pods
in `tuist-runners` on that host, using the same host as gateway and the allocated
IP explicitly. RFC1918, CGNAT and link-local destinations are excluded from
translation; NetworkPolicy still controls private access. Reconciliation repairs
policy drift and refreshes its revision after reboot. `RunnerEgressReady=True`
means configuration was applied; a real job must prove the resulting public IP.

## Deployment and qualification

1. Recheck block attachment, private-vRack alignment and address capacity. Keep
   staging's shared cache vRack. Build the provider with the existing provider
   image workflow, then use the normal deployment workflow with a matching
   `capi_image_tag`; the chart adds a manager flag older images do not understand.
   Preserve any newer staging changes in the deployment baseline.
2. For first installation, override `capi.ovhRunnerEgress.enabled=false`, then
   qualify staging first. Cordon hosts and wait
   for running jobs to finish before changing their egress identity. Keep the
   provider, ConfigMap and cleanup RBAC installed throughout activation/rollback.
   Avoid concurrent deployments that could replace the provider or its arguments.
3. Enable staging and verify every participating host's `RunnerEgressReady`,
   `tuist.dev/runner-egress-ip` and `tuist.dev/runner-egress-revision`. Confirm the
   revision includes its current BootID and private-network readiness remains
   True. Partially configured fleets still have jobs using primary IPs.
4. Confirm the private NIC is in Cilium's managed/masquerading devices and its
   BPF egress map selects the allocated IP and local gateway for runner sources.
   Inspect `ip -4 rule show priority 10430`, `ip -4 route show table 243`, and
   `ip -4 route get 1.1.1.1 from <allocated-address>`. Verify ordinary host traffic
   retains the primary route. Qualify any required Cilium device change before
   applying it across a cluster.
5. Resume scheduling and dispatch `linux-runners-staging-smoke.yml` with
   `gradle_cache=true`, `compile_project=true` and `expected_public_ip` set to the
   allocated address. Require real compilation, upload and remote restores with
   matching checksums. The fixture accepts staging's existing private runner
   cache and EU-West regional endpoints. Also verify DNS, image pulls, job/dind
   traffic, and denied access to private destinations outside existing allowances.
6. On drained staging hosts, qualify owned-route repair, reboot persistence
   before kubelet, disable/re-enable, and Machine deletion/replacement with safe
   address reuse. Repeat real-job checks after transitions. Provision and verify
   monitoring before promotion.
7. Align canary's block with `pn-2024092`, deploy the capable provider/configuration
   and explicitly enroll its drained existing runner into the private-cache
   vRack. The OnDelete template does not backfill existing Machine specs. Qualify
   canary's public IP and private cache together and run runner acceptance. Use
   the normal deployment workflow or human elevation for writes.
8. Publish `5.135.7.160/27` as the **upcoming** production Linux range in
   `server/priv/docs/en/guides/server/network.md` before switching production.
   Retain every current Linux /32 so both the transition and rollback remain
   allowlisted. Keep production disabled until users have had time to update
   their allowlists and the remaining qualification gates are complete. After
   separately authorized production activation, verify every host and retain the
   old /32s through the rollback window before announcing their removal. The
   macOS range `95.130.119.0/24` is unchanged.

## Rollback and deletion

Set `capi.ovhRunnerEgress.enabled=false` while retaining the provider, ConfigMap
and RBAC. Wait for the egress conditions, Node annotations and owned policies to
disappear and the reservation map to become empty before downgrading the provider.
Rollback returns jobs to primary IPs, so coordinate allowlist changes.
Changing the configured CIDR or vRack while reservations exist is rejected.

Machine deletion first waits for running jobs. Cleanup withdraws the Cilium
policy and confirms its absence on a subsequent read, then removes host state
before freeing the address, deleting SSH credentials or requesting reinstall.
It removes kubelet's egress dependency and reloads systemd **before** stopping
the egress service: reversing this order stopped kubelet during the first live
rollback drill because `Requires` propagates an explicit stop, even for an
inactive oneshot. A regression test covers this ordering and failed cleanup.
Private-cache identity, routes, reservations and repair timer remain intact.

An unreachable host retains its address and blocks the Machine finalizer.
Neither Machine absence nor acceptance of an asynchronous reinstall proves the
old OS no longer owns the IP. Restore access or obtain independent proof of
wipe/network isolation before reviewed manual recovery. Forced finalizer removal
deliberately leaves the reservation retained.

## Staging evidence and limits

Qualification used `ns3066567.ip-193-70-46.eu` on `pn-2023588`, private address
`172.30.241.4` and cache route via `172.30.241.2`. On 2026-10-27, integration
provider `e8dcb75e` preserved staging's Kura storage/nested-KVM baseline and
contained the PR's identical egress implementation. The
[build and provider-only deployment](https://github.com/tuist/tuist/actions/runs/40492616173)
passed without upgrading application/cache releases. This was an integration
image, not an image of the entire PR checkout.

| Check | Result |
| --- | --- |
| [Baseline](https://github.com/tuist/tuist/actions/runs/40493029798) | Exact `193.70.46.18`; both real Kotlin tasks uploaded and restored remotely with matching checksums. |
| [Enabled](https://github.com/tuist/tuist/actions/runs/40493880351) | Exact `5.39.98.145`; same private-cache compilation/restore checks passed. |
| [Rollback](https://github.com/tuist/tuist/actions/runs/40494320217) | Exact `193.70.46.18`; both remote restores passed after cleanup. |
| Repair timer, 2026-10-26 | Removing the owned table-243 default was repaired in 37 seconds; subsequent public-IP probe passed. |
| [Post-reboot](https://github.com/tuist/tuist/actions/runs/40415653210) | Egress restored before kubelet; exact allocated IP and both real Kotlin remote restores passed. |

The first compile-fixture recheck rejected the existing private-cache endpoint
before compilation. Its guard now permits that exact endpoint alongside the
regional names while retaining the staging-only URL restriction.

State after that rollback: provider `e8dcb75e`, egress disabled, empty
public reservations, egress conditions/annotations cleared, private networking
intact, runner Ready and schedulable. Temporary diagnostics and qualification
annotations were removed. The 2026-10-27 recheck used controller convergence and
real jobs; the human Kubernetes identity could not read the cluster-scoped
policy, so it did not repeat the earlier BPF-map/host inspection.

Staging was subsequently left **enabled** on 2026-10-27. After a concurrent Kura
deployment finished, provider `e8dcb75e` was restored without changing application
or cache releases. Activation waited for zero nonterminal runner pods on the
cordoned host, then verified egress/private-network/KVM readiness and resumed
scheduling. [Activation acceptance](https://github.com/tuist/tuist/actions/runs/40498958116)
passed with exact public IP `5.39.98.145` and both real Kotlin tasks restored from
the private cache. The egress revision matched the current BootID; the temporary
reconciliation annotation was removed. Canary's enabled values are desired state,
not evidence of live qualification: its block move and drained enrollment remain
deployment prerequisites. A deployment from a branch without this configuration
can overwrite staging's provider/flag, so preserve them in subsequent deployments.

**Remaining gates:** the earlier reboot took roughly ten minutes and triggered
OVH server-down monitoring. Busy kubelet mounts appeared in shutdown logs, but
the full delay's cause is unknown; the host booted an already-installed newer
kernel. Persistence passed, fast recovery did not. Machine replacement/address
reuse remains untested on the sole staging runner. Alerts are definitions only.
These limits and canary/production vRack alignment remain before promotion.

## Monitoring and local checks

`capt_runner_egress_info{node,mac,vrack,cidr}` joins `node_network_info` to private
NIC counters without relying on interface names. The Grafana definitions in
`infra/helm/k8s-monitoring/ovh-runner-egress-alert-rules.json` alert on sustained
transmit or receive above 80% of the 5 Gbps block limit for ten minutes. Provision
them separately into `Runner networking` with a one-minute evaluation interval;
preserve notification routing and verify `affected_service=Runners` reaches its
receiver. No-data is normal while disabled. Check every configured host has data
and evaluate each NIC's contracted bandwidth separately.

Run provider `go test ./...` with Bash 4+ on PATH and `TUIST_TEST_HELM` pointing
to Helm. Coverage includes allocation/exhaustion, ownership, failures, repair,
reboot revisions, cleanup/finalizer ordering, host-script simulation and managed
chart rendering. Shellcheck the host script and smoke fixture. Run
`infra/helm/k8s-monitoring/test-ovh-runner-egress-alert.sh` with jq and promtool for
the shipped alert expressions, multi-host aggregation, public-interface exclusion,
environment isolation and pending period. Local checks do not replace live jobs.
