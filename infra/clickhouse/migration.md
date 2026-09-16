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

## Reading a step

The launcher prints the Job's log. If you stop following, the Job keeps running, and the launcher prints the command to follow it again. Logs are also in Loki under `{namespace="<namespace>", container="clickhouse-migration"}`. Finished Jobs are deleted after a week.

`backfill` records each chunk in Postgres. Running it again skips finished chunks and retries failed ones, and a later cutoff turns the latest month into a new chunk. Only one backfill runs at a time: a second one fails without copying anything.

## The deploy hook

The chart can also run a step as a post-upgrade hook through `clickhouse.managed.migration`. Leave it disabled and use the launcher. A failing hook rolls the release back and blocks every deploy behind it.
