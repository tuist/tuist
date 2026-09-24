# Moving ClickHouse onto the in-cluster server

Each step runs as a one-off Kubernetes Job, launched from your machine:

```bash
cd infra
mise run clickhouse:migration <env> <step> [--cutoff <instant>] [--dry-run]
```

The launcher copies the server's migrate Job, so a step runs with the deployed image, service account, secrets and ClickHouse settings. It then follows the Job's log until the step finishes and exits non-zero if it failed. The Job is not part of the Helm release: a failed step fails its Job and nothing else.

## Access

The launcher uses the `tuist-k8s-<env>` kubectl contexts from the [cluster onboarding runbook](../k8s/onboarding.md). Staging is writable over the tailnet. On canary and production, run `/elevate <env> <duration> <intent>` in Slack before launching a step.

## Steps

| Step | Task | Writes |
|---|---|---|
| `clone` | `Tuist.Release.clone_clickhouse_schema` | Missing tables, views and columns on the in-cluster server |
| `backfill --cutoff <instant>` | `Tuist.Release.backfill_clickhouse` | Rows written before the cutoff, onto the in-cluster server |
| `parity` | `Tuist.Release.check_clickhouse_parity` | Nothing |
| `check-reads` | `Tuist.Release.check_clickhouse_reads` | Nothing |
| `enable-reads` | `Tuist.Release.enable_clickhouse_bare_metal_reads` | The flag that moves the application's reads |
| `disable-reads` | `Tuist.Release.disable_clickhouse_bare_metal_reads` | The flag that moves reads back |

For an environment, in order:

1. `clone`.
2. Turn on shadow writes in the environment's values (`clickhouse.managed.shadowWrites`) and deploy. This is the only step that goes through a deploy.
3. `backfill`, with `--cutoff` set after the shadow-writes deploy finished rolling out.
4. `parity`. If a table differs, fix the cause, run `backfill` again with a later cutoff, then `parity` again.
5. `check-reads`. It refuses to run once reads have moved.
6. `enable-reads`. `disable-reads` moves them back.
7. Make the in-cluster server the system of record: set `clickhouse.mode` to `managed` in the environment's values and deploy. Every workload then reads and writes it through `TUIST_CLICKHOUSE_URL`, and ClickHouse Cloud receives nothing. The launcher refuses every step from then on.

Before step 7:

- Run `parity` and `check-reads` again, and deploy the switch only if both pass. `parity` also fails when `schema_migrations` holds different versions on the two servers: the first deploy after the switch migrates the in-cluster server, and any version missing there runs again, including data migrations.
- Keep the switch in a deploy of its own, so the deploy it rolls back to still writes to both servers.

Going back to `external` after step 7 does not copy anything back: rows written since the switch exist only on the in-cluster server.

## Reading a step

The launcher prints the Job's log. If you stop following, the Job keeps running, and the launcher prints the command to follow it again. Logs are also in Loki under `{namespace="<namespace>", container="clickhouse-migration"}`. Finished Jobs are deleted after a week.

`backfill` records each chunk in Postgres. Running it again skips finished chunks and retries failed ones, and a later cutoff turns the latest month into a new chunk. Only one backfill runs at a time: a second one fails without copying anything.

## The deploy hook

The chart can also run a step as a post-upgrade hook through `clickhouse.managed.migration`. Leave it disabled and use the launcher. A failing hook rolls the release back and blocks every deploy behind it.
