# Registry repair runbook

Operator scripts for repairing Swift package registry state, plus a record of how
they are run. Context and measurements are in
[#12191](https://github.com/tuist/tuist/issues/12191).

These run **directly against production** rather than through a deploy, so they
live in the repository to be reviewable and repeatable rather than reconstructed
from shell history.

## Why `eval` and not `remote`

The `swift-registry-sync` pod runs with `RELEASE_DISTRIBUTION=none`:
`rel/env.sh.eex` only enables distribution when the chart supplies
`TUIST_CLUSTER_DNS_SERVICE` and `POD_IP`, and only the server Deployment sets
those. The node is therefore not alive, and `bin/tuist rpc` / `remote` fail with
`Cannot run --rpc-eval if the node is not alive`.

`bin/tuist eval` starts a separate BEAM that still evaluates `config/runtime.exs`,
so the registry bucket and credentials are configured. `boot.exs` supplies the
one missing piece — a Finch instance for `ex_aws` — and deliberately does not
start `:tuist`, which would boot a second Oban and consume release jobs
alongside the live pod.

`priv/` ships inside the release, so `SCRIPT` accepts a bare filename and no
files need copying into the pod.

## Work orders

| Mode | Population | Effect |
| --- | --- | --- |
| `catalog_restore` | Archive intact, catalog entry missing | Writes metadata only. **No byte changes**, so pinned consumers are healed silently |
| `regenerate` | Archive unextractable, or catalog advertises a version storage lacks | Enqueues the ordinary release worker with an explicit checksum-change override |

`regenerate` requires the `allow_checksum_change` option from
[#12193](https://github.com/tuist/tuist/pull/12193). `catalog_restore` runs
against the currently deployed release.

## Running

```sh
POD=$(kubectl --context "$CTX" -n "$NS" get pod \
  -l app.kubernetes.io/component=swift-registry-sync \
  -o jsonpath='{.items[0].metadata.name}')

kubectl --context "$CTX" -n "$NS" cp ./catalog_restore_input.csv \
  "$NS/$POD:/tmp/catalog_restore_input.csv" -c swift-registry-sync
```

Dry run first — nothing is written and nothing is logged, so the same input
applies cleanly afterwards:

```sh
kubectl --context "$CTX" -n "$NS" exec "$POD" -c swift-registry-sync -- \
  env SCRIPT=repair.exs \
      REPAIR_MODE=catalog_restore \
      REPAIR_INPUT=/tmp/catalog_restore_input.csv \
      REPAIR_LIMIT=20 \
  /app/bin/tuist eval 'Code.eval_file(Application.app_dir(:tuist, "priv/registry_repair/boot.exs"))'
```

Apply once the dry-run output looks right, raising the limit as confidence grows:

```sh
kubectl --context "$CTX" -n "$NS" exec "$POD" -c swift-registry-sync -- \
  env SCRIPT=repair.exs \
      REPAIR_MODE=catalog_restore \
      REPAIR_INPUT=/tmp/catalog_restore_input.csv \
      REPAIR_LIMIT=500 \
      REPAIR_APPLY=1 \
  /app/bin/tuist eval 'Code.eval_file(Application.app_dir(:tuist, "priv/registry_repair/boot.exs"))'
```

Regeneration, after #12193 has shipped. Keep the limit low: each entry enqueues a
job that calls GitHub, and the sync has been rate-limited to `403` under load.

```sh
kubectl --context "$CTX" -n "$NS" exec "$POD" -c swift-registry-sync -- \
  env SCRIPT=repair.exs \
      REPAIR_MODE=regenerate \
      REPAIR_INPUT=/tmp/unextractable_reachable.csv \
      REPAIR_LIMIT=25 \
      REPAIR_APPLY=1 \
  /app/bin/tuist eval 'Code.eval_file(Application.app_dir(:tuist, "priv/registry_repair/boot.exs"))'
```

## Options

| Variable | Default | Meaning |
| --- | --- | --- |
| `REPAIR_MODE` | required | `catalog_restore` or `regenerate` |
| `REPAIR_INPUT` | required | CSV path inside the pod |
| `REPAIR_APPLY` | unset | `1` writes; anything else is a dry run |
| `REPAIR_LIMIT` | `100` | entries processed this run |
| `REPAIR_LOG` | `/tmp/repair_log.tsv` | applied decisions; already-recorded entries are skipped |
| `REPAIR_VERIFY` | `1` | hash the stored archive rather than trusting the published checksum |

## Safety properties

- **Dry run by default.** Dry runs are not logged, so an input can be inspected
  and then applied.
- **Resumable.** Every applied decision is appended to `REPAIR_LOG` and those
  identifiers are skipped on subsequent runs, so a run can be interrupted or
  repeated freely.
- **`catalog_restore` never writes archive bytes.** It hashes the stored archive
  and, when a published checksum is known, refuses to write if the two disagree —
  the guard against advertising a checksum object storage does not hold, which is
  the failure this repair exists to undo.
- **Locking.** Metadata is re-read and written under the same package lock the
  release worker takes, so a repair cannot race the live sync.
- **`regenerate` reuses `ReleaseWorker`** through the force path rather than
  reimplementing archive construction. It passes `allow_checksum_change: true`,
  correct here because both populations are unusable today and so no working pin
  exists to break.

Column 4 differs between inputs — a published checksum in
`catalog_restore_input.csv`, free text in `unextractable_reachable.csv` — so it is
accepted only when it is a valid sha256, and a detail string can never reach a
catalog entry.

## Input files

Samples are in `samples/`, using public packages and synthetic checksums. The real
inputs are derived from a storage/catalog/baseline join and are not committed:
they enumerate which packages and versions each account served and consumed.
