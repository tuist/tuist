# Hetzner Robot Controller

Reflects Robot inventory into `HetznerBareMetalHost` CRs and fills disk hints/provider IDs. caph owns rescue, installimage, and kubeadm join; do not duplicate that lifecycle here.

- Touch only CRs labeled `app.kubernetes.io/managed-by=hetzner-robot-controller`; leave hand-authored/unmanaged CRs alone.
- Never reap an inventory-missing CR while `spec.consumerRef.name` is set: caph still owns the binding. Operator recovery must drain/unbind the MachineDeployment before inventory cleanup.
- Keep shared-account environment isolation: derive partitions from Cluster `bareMetalCluster` topology variables, match operator `tuist-bm-<env>-…` and caph-rewritten `bm-<clusterCRName>-…` names, longest-prefix first. Stamp `tuist.dev/cluster` and preserve matching host selectors; only fall back to the legacy name-prefix gate when no partition is configured.
- Never overwrite operator-selected disk hints; single-disk hosts require explicit hints. Automatic selection uses the highest-capacity same-size disk group with at least two distinct WWNs, not the first two disks. Keep `statefulRaidLevel` aligned: RAID 1 for two disks, RAID 10 for four.
- Keep inventory polling leader-elected. Provider-ID repair targets the bound workload Node, not arbitrary hosts.
- Deployment/RBAC integration: [management manifest](../k8s/mgmt/hetzner-robot-controller.yaml). Operator procedures belong in [onboarding](../k8s/onboarding.md); parent agent access rules still apply.

## Disk selection

caph requires `spec.rootDeviceHints` populated before installimage can run,
but discovers WWNs during rescue and only writes `spec.status.hardwareDetails`:
`spec` is operator intent. Fill empty hints with the highest-capacity same-size
group, not every disk: mdadm sizes every member to the smallest, so mixing two
1.92 TB disks with two 7.68 TB disks wastes most of the flash, and the layout
is fixed at install. Skip groups too small to mirror. The RAID level comes
from the `statefulRaidLevel` ClusterClass variable, not this controller; it
must match the selection (1 for two disks, 10 for four).

Net: the operator's bring-up workflow becomes "order in Robot
panel with `tuist-bm-staging-N` naming → bump replicas." No
hand-authored CRs, no WWN-copying, no `kubectl create secret`
ceremony per host.

## Configuration

| Flag                              | Default                                                | Purpose                                                                  |
| --------------------------------- | ------------------------------------------------------ | ------------------------------------------------------------------------ |
| `--host-namespace`                | `org-tuist`                                            | Namespace where HetznerBareMetalHost CRs live                            |
| `--name-prefix`                   | `tuist-bm-`                                            | Robot servers outside this prefix are ignored (creation AND deletion)    |
| `--poll-interval`                 | `60s`                                                  | How often to poll Robot. Hardware procurement is human-paced.            |
| `--robot-user-path`               | `/etc/hetzner-robot-controller/robot-user`             | File the chart mounts from `org-tuist/hetzner` Secret                    |
| `--robot-pass-path`               | `/etc/hetzner-robot-controller/robot-pass`             | Same                                                                     |
| `--leader-elect`                  | `true`                                                 | Required when `replicas > 1`                                             |

## Fleet credentials

Robot user/pass and the shared SSH key are fleet-level (one Hetzner
Robot account spans every Robot host across staging, canary and
production), so both 1Password items live in the mgmt cluster's own
vault (`tuist-k8s-mgmt`).

These fleet Secrets remain operator-managed; the management deployment's
Secret references are authoritative. The mgmt cluster now has ESO for Flux
bootstrap, but that does not automatically migrate the Robot credentials.
Bootstrap and emergency access are human operator
references, not permission for agents to read Secrets or bypass parent access
rules. Provision `HETZNER_WEBSERVICE` credentials into the shared
`org-tuist/hetzner` Secret (`hetzner-robot-user` and `hetzner-robot-password`),
not a separate controller-only copy. The
[bare-metal templates](../k8s/clusters/bare-metal.yaml) also require
`org-tuist/hetzner-bare-metal-ssh-key` from `HETZNER_BARE_METAL_SSH_KEY`, with
`sshkey-name`, `ssh-publickey` and `ssh-privatekey`. Keep caph and this
controller's credential wiring aligned; remove temporary credential files
after any human-run bootstrap.

An explicit migration to `ExternalSecret` resources next to the
`infra/k8s/clusters/bare-metal*.yaml` templates can replace this manual step;
preserve the shared-account credential scope and verify the live Secret keys.

### Emergency SSH access

If a Robot host misbehaves and caph isn't responding, SSH in directly
with the shared key. caph configures it into
`/root/.ssh/authorized_keys` as part of the cloud-init bootstrap, so it
stays valid through reinstalls:

```bash
op read "op://tuist-k8s-mgmt/HETZNER_BARE_METAL_SSH_KEY/private-key" \
  --account=tuist.1password.com > /tmp/hbm
chmod 600 /tmp/hbm
ssh -i /tmp/hbm root@<host-ip>
# remember to: shred -u /tmp/hbm afterwards
```

## Selection conventions

**Server name** (operator sets in Robot panel):

```
tuist-bm-<env>-<n>
```

Examples: `tuist-bm-staging-1`, `tuist-bm-canary-2`,
`tuist-bm-production-7`. Servers outside this naming are ignored
by the controller — useful escape hatch for one-off boxes that
shouldn't auto-adopt.

**CR name** (controller derives, deterministic):

```
bm-<robot-server-id>
```

Example: `bm-2986829`. Stable so an operator can map between
the Robot panel and the CR list at a glance. `kubectl -n org-tuist
get hetznerbaremetalhost` shows them in numerical order.

**Labels stamped on every managed CR**:

| Label                                  | Value                                | Why                                                              |
| -------------------------------------- | ------------------------------------ | ---------------------------------------------------------------- |
| `app.kubernetes.io/managed-by`         | `hetzner-robot-controller`           | Scopes "what's mine" for the deletion pass and the WWN watcher  |
| `robot.hetzner.com/server-number`      | `2986829` (as string)                | Queryable from kubectl                                          |
| `robot.hetzner.com/server-name`        | `tuist-bm-staging-1`                 | The Robot panel name (caph rewrites this during provisioning) |
| `tuist.dev/cluster`                    | `staging`                            | Per-env partition for the shared Robot account; HBMM `hostSelector` matches on this |

## Per-cluster partitioning

The Robot account is shared across `staging`, `canary`, `production`,
and any future CAPI clusters. The controller discovers which envs
exist by listing CAPI `Cluster` CRs in `org-tuist` and reading each
one's `spec.topology.variables[name=bareMetalCluster].value` — that
value is the env's short label (`staging`, `canary`, `production`).

A Robot server is included in inventory only if its name parses to
one of those envs via either of:

- `tuist-bm-<envLabel>-…` — operator's name in the Robot panel.
- `bm-<clusterCRName>-…` — caph rewrites the Robot server name to
  `bm-<HBMM-name>` during provisioning; HBMMs are CAPI-templated as
  `<clusterCRName>-<deploymentName>-…`. Note `clusterCRName` is the
  Cluster CR's `metadata.name` — which doesn't always follow the
  `tuist-<env>` convention (production's CR is just `tuist`).

Longest-prefix wins so a short Cluster name like `tuist` (production)
can't accidentally swallow `tuist-staging`-prefixed servers.

The matched env gets stamped on the HBM as `tuist.dev/cluster`, and
each env's `HetznerBareMetalMachineTemplate.spec.template.spec.hostSelector`
filters on it:

```yaml
hostSelector:
  matchLabels:
    app.kubernetes.io/managed-by: hetzner-robot-controller
    tuist.dev/cluster: staging
```

Existing CRs that pre-date the label get back-filled on the next sync
based on `robot.hetzner.com/server-name`. If no Cluster CR sets
`bareMetalCluster`, the gate is off and the controller falls back to
the legacy `--name-prefix` filter (single-env mode).

## Cascade safety on deletion

If Robot stops reporting a server (cancellation, rename out of
prefix), the next sync would normally reap the matching CR. We
refuse to delete a CR if `spec.consumerRef.name` is set — that
indicates caph has bound it to a `HetznerBareMetalMachine`, and
dropping the CR would leave caph reconciling against a missing
reference until the operator manually drains the MD. The
controller emits a log line; the operator's recovery path is
`replicas → 0` on the MD, wait for unbind, then next sync reaps
the orphan.

We also never touch CRs that lack the managed-by label. A
hand-authored CR (for an off-convention box) is safe from
controller drift.

## Tests

Run `go test ./...` here.

Coverage:
- `InventorySyncer.sync`: creates missing, skips prefix mismatch,
  deletes stale, refuses claimed, refuses unmanaged, skips
  cancelled, idempotent multi-pass, name function shape.
- `WWNFillReconciler.Reconcile`: fills from hardwareDetails,
  skips unmanaged, skips already-populated single-disk hint,
  waits for enough disks, skips when hardwareDetails absent,
  dedupes WWNs.
- `extractWWNs`: skips entries without WWN, malformed entries.

Tests use controller-runtime's `fake.Client` and an in-memory
`robot.FakeClient` — no live Robot API or k8s cluster required.

## Releasing

`.github/workflows/hetzner-robot-controller-release.yml` cuts the
tag and publishes the image on push to `main`, and the mgmt cluster
runs whatever tag `infra/k8s/mgmt/hetzner-robot-controller.yaml`
pins. Renovate raises the pin once a release exists.

What makes a commit releasable is the **paths it touches**, not its
scope. `include_paths` in `mise/tasks/release/components.json`
restricts the range to this directory, and `cliff.toml` then accepts
any conventional commit in it apart from `chore` and `ci`. A change
landing under `feat(server)` or `fix(infra)` releases exactly as one
under `fix(hetzner-robot-controller)` does.

`cliff.toml` used to match on the scope instead, and that is how the
WWN four-disk fix shipped nowhere. It merged under `feat(server)` in
[#12814](https://github.com/tuist/tuist/pull/12814), `release:check`
found nothing releasable, the release job was skipped by
`if: needs.check.outputs.should-release == 'true'`, and the mgmt
cluster kept running `0.1.0` with a filler that installs a four-disk
box across two of its disks. Nothing reported it: CI was green and
`main` carried the fix, so the drift was visible only by comparing
the pin against the code.

## Future work

- **Webhook on the CR for the deletion gate** (admission rejection
  instead of just logged refusal). Helps when a human accidentally
  `kubectl delete`s a claimed host.
- **Single-disk host support** (currently the WWN-fill always
  writes `rootDeviceHints.raid.wwn`; if a future box ships with
  one disk the operator has to set `rootDeviceHints.wwn`
  manually).
- **Status updates on the CR** so operators can see
  `controller.tuist.dev/last-reconciled-at` timestamps without
  reading logs.
