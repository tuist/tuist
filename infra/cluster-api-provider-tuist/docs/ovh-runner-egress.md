# OVH Linux runner egress

`capi.ovhRunnerEgress` routes runner jobs through one OVH Additional IP block
per environment. All three blocks are delivered and attached to the vRacks
below, as confirmed by the supplied OVH Manager screenshots. Egress remains
**disabled in every environment** pending resolution of the existing staging
private network and qualification on staging. No public
allowlist documentation changes until production has passed the checks below.

| Environment | Attached vRack | Delivered block | Usable addresses | Gateway |
| --- | --- | --- | --- | --- |
| staging | pn-2025489 | 5.39.98.144/29 | 5.39.98.145–5.39.98.149 (5) | 5.39.98.150 |
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
Physical routing and device selection still require the staging qualification.

## Staging findings on 2026-10-26

Read-only inspection found two Ready Linux runner Machines, not one:

- `tuist-tuist-ovh-fleet-runners-linux-h72m4-llfpg`: service
  `ns3066567.ip-193-70-46.eu`, kernel 6.8.0-139. Its Node already carries
  `tuist.dev/private-network=pn-2023588`, the **cache** vRack, and the retained
  cache reservation map assigns it `172.30.241.4`.
- `tuist-tuist-ovh-fleet-runners-linux-h72m4-wf682`: service
  `ns340020.ip-37-187-143.eu`, kernel 6.8.0-142, with no private-network Node
  annotation in that read.

The first host's Cilium 1.18.7 reports both `enp6s0` (public) and `enp7s0`
(private, `172.30.241.4`) as managed devices. BPF masquerading and egress
Gateway are enabled cluster-wide. This is evidence about that host only.

**Resolve the existing cache-network enrollment before enabling the planned
runner vRack.** Determine whether it is a temporary experiment to retire or an
intended private path to preserve. Do not move the NIC or discard the cache
reservation to make the new controller progress. Both the annotation preflight
and OVH attachment check refuse that move. The feature can use an existing
vRack if that becomes the reviewed design and the public block is attached
there, but that changes the separate-network plan above.

## Qualification and rollout

1. Recheck the recorded block/vRack associations before activation; delivery
   and attachment are confirmed in OVH Manager. Resolve the staging conflict
   above. Confirm enough
   usable addresses for hosts plus replacement surge; retained failed-cleanup
   reservations consume capacity.
2. Deploy the provider and charts with egress disabled and the recorded CIDRs.
   After resolving the staging conflict, enable only staging. Read
   `RunnerEgressReady` and both Node
   annotations. A partial fleet rollout leaves unconfigured hosts on their
   primary public IP; do not promise the new allowlist yet.
   The chart adds an operator flag, so use the matching provider release. For
   pre-release staging checks, pin its built image with the deployment
   workflow's `capi_image_tag` input; an older image will reject the flag.
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
