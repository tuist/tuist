# hetzner-robot-controller

Small operator that fills the gap between [caph](https://github.com/syself/cluster-api-provider-hetzner)
(the upstream CAPI provider for Hetzner) and the Tuist operator
workflow for adopting Hetzner Robot bare-metal hosts. caph is
the CAPI provider — it claims `HetznerBareMetalHost` CRs and
drives them through rescue/installimage/kubeadm-join. This
controller does the two things caph deliberately doesn't:

1. **Reflects Robot inventory into CRs.** caph adopts existing
   hosts; it doesn't discover them. Operator orders a box in the
   Robot panel under the `tuist-bm-*` naming convention; the
   controller polls Robot every 60s and creates a matching
   `HetznerBareMetalHost` CR. Cancellations delete the CR.

2. **Auto-fills disk WWNs.** caph requires
   `spec.rootDeviceHints` populated before installimage can run,
   but caph itself discovers WWNs during the rescue boot and
   only writes them to `spec.status.hardwareDetails` (a deliberate
   safety — `spec` is operator intent). The controller watches
   for hosts where `hardwareDetails` is populated but
   `rootDeviceHints` is empty, and patches the first two WWNs
   into `spec.rootDeviceHints.raid.wwn` (RAID 1 layout matching
   Hetzner's default for AX-class hardware).

Net: the operator's bring-up workflow becomes "order in Robot
panel with `tuist-bm-staging-N` naming → bump replicas." No
hand-authored CRs, no WWN-copying, no `kubectl create secret`
ceremony per host.

## Architecture

```
Robot webservice (https://robot.hetzner.com/api)
        │
        │ ServerGetList()
        │ poll every 60s
        ▼
┌──────────────────────────────────────────────┐
│ hetzner-robot-controller-manager             │
│ (mgmt cluster, org-tuist namespace)          │
│                                              │
│   ┌─────────────────────────────────────┐   │
│   │ InventorySyncer (Runnable)          │   │
│   │  - leader-elected (singleton)       │   │
│   │  - filters by `tuist-bm-` prefix    │   │
│   │  - creates CRs for new servers      │   │
│   │  - deletes CRs for cancelled boxes  │   │
│   │    (refuses if caph has claimed)    │   │
│   └─────────────────────────────────────┘   │
│                                              │
│   ┌─────────────────────────────────────┐   │
│   │ WWNFillReconciler (event-driven)    │   │
│   │  - watches HetznerBareMetalHost     │   │
│   │  - filters managed-by label         │   │
│   │  - when hardwareDetails has WWNs    │   │
│   │    and rootDeviceHints is empty:    │   │
│   │    patch rootDeviceHints.raid.wwn   │   │
│   └─────────────────────────────────────┘   │
└────────────────────┬─────────────────────────┘
                     │ creates / patches
                     ▼
       HetznerBareMetalHost CRs (caph claims these)
```

## Module layout

```
infra/hetzner-robot-controller/
├── AGENTS.md             # (this file)
├── Dockerfile
├── cliff.toml
├── CHANGELOG.md
├── go.mod
├── go.sum
├── cmd/manager/main.go   # flags, manager setup, controller wiring
├── controllers/
│   ├── hostdiscovery.go      # InventorySyncer Runnable
│   ├── hostdiscovery_test.go
│   ├── wwnfill.go            # WWNFillReconciler
│   └── wwnfill_test.go
├── internal/robot/
│   └── client.go             # hrobot-go SDK wrapper + FakeClient
└── config/rbac/role.yaml     # ClusterRole the chart binds
```

The mgmt-cluster Deployment manifest lives at
[`infra/k8s/mgmt/hetzner-robot-controller.yaml`](../k8s/mgmt/hetzner-robot-controller.yaml)
and is applied by `mgmt-cluster-apply.yml`.

## Configuration

| Flag                              | Default                                                | Purpose                                                                  |
| --------------------------------- | ------------------------------------------------------ | ------------------------------------------------------------------------ |
| `--host-namespace`                | `org-tuist`                                            | Namespace where HetznerBareMetalHost CRs live                            |
| `--name-prefix`                   | `tuist-bm-`                                            | Robot servers outside this prefix are ignored (creation AND deletion)    |
| `--poll-interval`                 | `60s`                                                  | How often to poll Robot. Hardware procurement is human-paced.            |
| `--robot-user-path`               | `/etc/hetzner-robot-controller/robot-user`             | File the chart mounts from `org-tuist/hetzner` Secret                    |
| `--robot-pass-path`               | `/etc/hetzner-robot-controller/robot-pass`             | Same                                                                     |
| `--leader-elect`                  | `true`                                                 | Required when `replicas > 1`                                             |

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
| `robot.hetzner.com/server-name`        | `tuist-bm-staging-1`                 | Lets `HetznerBareMetalMachineTemplate.spec.template.spec.hostSelector` match by env |

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

```bash
cd infra/hetzner-robot-controller
go test ./...
```

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
