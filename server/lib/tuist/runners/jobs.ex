defmodule Tuist.Runners.Jobs do
  @moduledoc """
  ClickHouse-backed lifecycle table for workflow_jobs. The
  `runner_jobs` ReplacingMergeTree carries one logical row per
  `workflow_job_id`; every state transition is an INSERT that
  advances the version column (`updated_at`) and RMT merge keeps
  the latest row per key.

  This module is **state-recording + read-only views**. Claim
  atomicity and per-account cap counting live in
  `Tuist.Runners.Claims` (a thin Postgres table). The split:

    * **Postgres `runner_claims`** is the OLTP claim lock. One
      row per currently-claimed workflow_job; PK on
      `workflow_job_id` gives atomic INSERT-ON-CONFLICT-DO-NOTHING.
      Cap counting is an indexed `GROUP BY account_id` against
      this table.
    * **ClickHouse `runner_jobs` (here)** is the customer-facing
      view + history. Powers the "what's queued / running right
      now / recent runs" surfaces and the analytics dashboards.

  Protocol: every state transition that touches the PG lock pairs
  with an INSERT here so the customer view stays in sync.

      queued → claimed → running → completed
                  ↑          ↓
                  └── release/stale recovery

  ## State machine

  Each transition is an INSERT carrying ALL columns forward from
  the previous state plus the updated fields — RMT merges on
  `(workflow_job_id)` keeping the latest `updated_at`, so columns
  not refreshed by the new INSERT would otherwise revert.

  ## Idempotency

  Webhook retries of `workflow_job.queued` INSERT another row
  with the same `workflow_job_id`. RMT merge collapses them; both
  rows carry the same `queued` state so the merge is a no-op
  visible to clients.

  ## Read pattern (no `FINAL`)

  RMT `FINAL` forces ClickHouse to merge matching parts at query
  time, which scales poorly as the table grows. We read the
  "latest row per workflow_job_id" the same way `Tuist.Tests`
  does: `argMax(col, updated_at)` aggregated by `workflow_job_id`
  for multi-row queries, and `ORDER BY updated_at DESC LIMIT 1`
  for single-row lookups. Both patterns use the merge-tree index
  and avoid the per-query merge cost.
  """

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Runners.Job
  alias Tuist.Runners.Telemetry

  require Logger

  # Pre-1970 sentinel used for "not yet set" timestamp slots. Any
  # timestamp at or below this epoch is treated as missing when
  # computing telemetry durations so a delivery-race `completed`
  # (no `started_at`) doesn't emit a multi-decade run_time spike.
  @epoch ~U[1970-01-01 00:00:00.000000Z]

  @doc """
  Idempotent enqueue. Inserts a `status='queued'` row for the
  workflow_job. Called from the `workflow_job.queued` webhook.
  """
  def enqueue(attrs) when is_map(attrs) do
    now = DateTime.utc_now()

    row =
      attrs
      |> Map.put(:status, "queued")
      |> Map.put_new(:enqueued_at, now)
      |> Map.put_new(:claimed_at, epoch())
      |> Map.put_new(:started_at, epoch())
      |> Map.put_new(:completed_at, epoch())
      |> Map.put(:updated_at, now)

    insert_row!(row)

    :telemetry.execute(
      Telemetry.event_name_job_enqueued(),
      %{count: 1},
      %{fleet: Map.get(row, :fleet_name, "")}
    )

    :ok
  end

  @doc """
  Picks the oldest queued candidate on `fleet_name`. The
  caller's responsibility to then atomically claim it via
  `Tuist.Runners.Claims.attempt/4`.

  `ineligible_account_ids` is the set of accounts already at
  cap (built by the caller from `Claims.counts_per_account/1`
  + the per-account `runner_max_concurrent`). Returns the
  candidate's full metadata so we can carry it forward on the
  `claimed` INSERT.

  Deterministic ordering — `(enqueued_at ASC, workflow_job_id
  ASC)` — means two concurrent pollers see the SAME row as the
  next candidate. The actual claim race then collapses on
  Postgres uniqueness in `Claims.attempt/4`.
  """
  def pick_queued(fleet_name, ineligible_account_ids \\ [])
      when is_binary(fleet_name) and is_list(ineligible_account_ids) do
    from(j in Job,
      where: j.fleet_name == ^fleet_name,
      group_by: j.workflow_job_id,
      having: fragment("argMax(?, ?) = ?", j.status, j.updated_at, "queued"),
      select: %{
        workflow_job_id: j.workflow_job_id,
        account_id: fragment("argMax(?, ?)", j.account_id, j.updated_at),
        fleet_name: fragment("argMax(?, ?)", j.fleet_name, j.updated_at),
        repo: fragment("argMax(?, ?)", j.repo, j.updated_at),
        workflow_run_id: fragment("argMax(?, ?)", j.workflow_run_id, j.updated_at),
        run_attempt: fragment("argMax(?, ?)", j.run_attempt, j.updated_at),
        job_name: fragment("argMax(?, ?)", j.job_name, j.updated_at),
        head_branch: fragment("argMax(?, ?)", j.head_branch, j.updated_at),
        head_sha: fragment("argMax(?, ?)", j.head_sha, j.updated_at),
        enqueued_at: fragment("argMax(?, ?)", j.enqueued_at, j.updated_at)
      }
    )
    |> exclude_accounts(ineligible_account_ids)
    |> order_by([j], asc: fragment("argMax(?, ?)", j.enqueued_at, j.updated_at), asc: j.workflow_job_id)
    |> limit(1)
    |> ClickHouseRepo.one()
    |> case do
      nil -> {:error, :empty}
      candidate -> {:ok, candidate}
    end
  end

  defp exclude_accounts(query, []), do: query

  defp exclude_accounts(query, account_ids) when is_list(account_ids) do
    having(query, [j], fragment("argMax(?, ?)", j.account_id, j.updated_at) not in ^account_ids)
  end

  @doc """
  Records the `claimed` state transition for customer visibility.
  Called after `Claims.attempt/4` succeeds and we're about to mint.
  """
  def record_claimed(candidate, pod_name, claimed_at) when is_map(candidate) and is_binary(pod_name) do
    now = DateTime.utc_now()

    row = Map.merge(candidate, %{status: "claimed", claimed_at: claimed_at, pod_name: pod_name, updated_at: now})

    insert_row!(row)

    :telemetry.execute(
      Telemetry.event_name_job_claim(),
      %{count: 1, queue_time_ms: duration_ms(candidate[:enqueued_at], claimed_at)},
      %{fleet: Map.get(candidate, :fleet_name, ""), outcome: "ok"}
    )

    :ok
  end

  @doc """
  Records the `running` state — JIT mint succeeded, runner is
  about to register with GitHub.
  """
  def record_running(workflow_job_id, runner_name) when is_integer(workflow_job_id) and is_binary(runner_name) do
    case current(workflow_job_id) do
      nil ->
        Logger.warning("runners: no CH row to transition to running",
          workflow_job_id: workflow_job_id
        )

        :ok

      %Job{} = job ->
        now = DateTime.utc_now()

        row =
          job
          |> job_to_row()
          |> Map.merge(%{
            status: "running",
            started_at: now,
            runner_name: runner_name,
            updated_at: now
          })

        insert_row!(row)

        :telemetry.execute(
          Telemetry.event_name_job_running(),
          %{
            count: 1,
            queue_to_running_ms: duration_ms(job.enqueued_at, now),
            claim_to_running_ms: duration_ms(job.claimed_at, now)
          },
          %{fleet: job.fleet_name || ""}
        )

        :ok
    end
  end

  @doc """
  Records the `queued` state — re-surfaces the workflow_job as
  claimable after a release / stale-recovery. The caller is
  responsible for having already DELETE'd the matching PG claim.
  """
  def record_queued(workflow_job_id) when is_integer(workflow_job_id) do
    case current(workflow_job_id) do
      nil ->
        :ok

      %Job{} = job ->
        now = DateTime.utc_now()

        row =
          job
          |> job_to_row()
          |> Map.merge(%{
            status: "queued",
            claimed_at: epoch(),
            pod_name: "",
            updated_at: now
          })

        insert_row!(row)

        :telemetry.execute(
          Telemetry.event_name_job_requeued(),
          %{count: 1},
          %{fleet: job.fleet_name || ""}
        )

        :ok
    end
  end

  @doc """
  Marks a job `completed` and records the GitHub conclusion. Called
  from the `workflow_job.completed` webhook handler. Idempotent —
  RMT merge collapses repeated completions to the latest
  `updated_at`.

  Returns `{:ok, %Job{}}` if the job was found and transitioned,
  or `{:error, :not_found}` if no row exists for the workflow_job
  yet (delivery race where `completed` arrives before `queued`).
  """
  def complete(workflow_job_id, conclusion) when is_integer(workflow_job_id) and is_binary(conclusion) do
    case current(workflow_job_id) do
      nil ->
        {:error, :not_found}

      %Job{} = job ->
        now = DateTime.utc_now()

        row =
          job
          |> job_to_row()
          |> Map.merge(%{
            status: "completed",
            conclusion: conclusion,
            completed_at: now,
            updated_at: now
          })

        insert_row!(row)

        :telemetry.execute(
          Telemetry.event_name_job_completed(),
          %{
            count: 1,
            run_time_ms: duration_ms(job.started_at, now),
            queue_time_ms: duration_ms(job.enqueued_at, job.claimed_at),
            total_time_ms: duration_ms(job.enqueued_at, now)
          },
          %{
            fleet: job.fleet_name || "",
            conclusion: normalise_conclusion(conclusion)
          }
        )

        {:ok,
         Map.merge(job, %{
           status: "completed",
           conclusion: conclusion,
           completed_at: now,
           updated_at: now
         })}
    end
  end

  @doc """
  Counts `queued` rows for `fleet_name`. Used by the autoscaler
  to size the warm pool — every queued workflow_job needs a Pod
  to claim it, so the desired replica count grows with this
  value. `argMax(status, updated_at)` picks the latest state per
  `workflow_job_id` so jobs that have since transitioned out of
  `queued` don't get double-counted.
  """
  def queued_count_by_fleet(fleet_name) when is_binary(fleet_name) do
    inner =
      from j in Job,
        where: j.fleet_name == ^fleet_name,
        group_by: j.workflow_job_id,
        having: fragment("argMax(?, ?) = ?", j.status, j.updated_at, "queued"),
        select: j.workflow_job_id

    from(s in subquery(inner), select: count())
    |> ClickHouseRepo.one()
    |> Kernel.||(0)
  end

  @doc """
  Computes the rolling p95 of concurrent (claimed + running) jobs
  on `fleet_name` over the last 60 minutes, in one-minute buckets.

  How: bucket the last 60 minutes; for each minute, count
  workflow_jobs whose `[claimed_at, completed_at]` interval covers
  the bucket. Take `quantile(0.95)` over the 60 counts.

  Powers the autoscaler's "lead the demand" behavior — when load
  ebbs after a peak, the warm pool floor stays at p95 for another
  hour so the *next* peak feels instant. Without it, every peak
  pays the full cold-start tax.

  Returns 0 on an empty fleet (no rows) or a brand-new fleet (no
  history yet) — both are the same as "no signal, use the
  configured static floor."

  Note on RMT semantics: rows for completed jobs carry
  `completed_at` set to the completion timestamp; rows still in
  flight carry `completed_at = epoch`, so the interval check
  matches on `completed_at > bucket OR completed_at = epoch`. The
  2-hour scan window bounds the work — jobs that completed more
  than two hours ago can't overlap any bucket inside the last
  60 minutes, so excluding them is a free perf win.
  """
  def p95_concurrent_last_hour(fleet_name) when is_binary(fleet_name) do
    query = """
    SELECT toUInt64(quantile(0.95)(concurrent_count)) AS p95
    FROM (
      SELECT
        b.bucket AS bucket,
        countIf(
          j.claimed_at <= b.bucket
          AND (
            j.completed_at > b.bucket
            OR j.completed_at = toDateTime64('1970-01-01 00:00:00.000', 6, 'UTC')
          )
        ) AS concurrent_count
      FROM (
        SELECT toStartOfMinute(now() - toIntervalMinute(number)) AS bucket
        FROM numbers(60)
      ) AS b
      CROSS JOIN (
        SELECT
          argMax(claimed_at, updated_at) AS claimed_at,
          argMax(completed_at, updated_at) AS completed_at
        FROM runner_jobs
        WHERE fleet_name = {fleet:String}
          AND claimed_at >= now() - toIntervalHour(2)
          AND claimed_at != toDateTime64('1970-01-01 00:00:00.000', 6, 'UTC')
        GROUP BY workflow_job_id
      ) AS j
      GROUP BY b.bucket
    )
    """

    case ClickHouseRepo.query(query, %{fleet: fleet_name}) do
      {:ok, %{rows: [[p95]]}} when is_integer(p95) -> p95
      _ -> 0
    end
  end

  @doc """
  Counts jobs in each lifecycle state for an account. Useful for
  customer dashboards.
  """
  def status_counts(account_id) when is_integer(account_id) do
    inner =
      from j in Job,
        where: j.account_id == ^account_id,
        group_by: j.workflow_job_id,
        select: %{
          workflow_job_id: j.workflow_job_id,
          status: fragment("argMax(?, ?)", j.status, j.updated_at)
        }

    from(s in subquery(inner),
      group_by: s.status,
      select: {s.status, count(s.workflow_job_id)}
    )
    |> ClickHouseRepo.all()
    |> Map.new()
  end

  @doc """
  Lists `runner_jobs` rows in `status = 'running'` whose
  `started_at` is older than `threshold` — candidates for the
  "Pod minted a JIT but the GitHub runner never registered"
  recovery path. `OrphanedRunnersWorker` cross-checks each
  candidate against GitHub's view of the workflow_job; if GH
  still reports `queued`, the runner never came up and we
  release + re-queue.

  Returns a list of maps carrying everything the worker needs
  (`repo` for the GH API call, `claimed_at` for the PG release
  handle), so the worker doesn't need a second round trip.
  """
  def list_orphaned_running(%DateTime{} = threshold) do
    Job
    |> from(hints: ["FINAL"])
    |> where([j], j.status == "running" and j.started_at < ^threshold)
    |> select([j], %{
      workflow_job_id: j.workflow_job_id,
      account_id: j.account_id,
      repo: j.repo,
      claimed_at: j.claimed_at,
      started_at: j.started_at,
      pod_name: j.pod_name
    })
    |> ClickHouseRepo.all()
  end

  # ----- internal -----

  # Fetch the current state of a workflow_job. Single-row lookup
  # by primary key — `ORDER BY updated_at DESC LIMIT 1` returns
  # the latest INSERT without forcing a part-merge.
  defp current(workflow_job_id) do
    Job
    |> where([j], j.workflow_job_id == ^workflow_job_id)
    |> order_by([j], desc: j.updated_at)
    |> limit(1)
    |> ClickHouseRepo.one()
  end

  defp insert_row!(row) do
    row = Map.put_new(row, :updated_at, DateTime.utc_now())
    IngestRepo.insert_all(Job, [row])
  end

  defp job_to_row(%Job{} = job) do
    job
    |> Map.from_struct()
    |> Map.delete(:__meta__)
  end

  defp epoch, do: @epoch

  # Returns `nil` when either bound is missing/epoch so the
  # histogram bucketer drops the sample instead of recording a
  # garbage duration.
  defp duration_ms(%DateTime{} = from, %DateTime{} = to) do
    if DateTime.after?(from, @epoch) and DateTime.after?(to, from) do
      DateTime.diff(to, from, :millisecond)
    end
  end

  defp duration_ms(_, _), do: nil

  # Normalise GH conclusion strings into the bounded tag set the
  # dashboard groups by. `nil` and `""` collapse to `"unknown"`
  # so the conclusion-by-rate panel doesn't grow a phantom empty
  # series for in-flight rows that crash through the orphan
  # recovery path.
  defp normalise_conclusion(c) when c in [nil, ""], do: "unknown"
  defp normalise_conclusion(c) when is_binary(c), do: c
  defp normalise_conclusion(_), do: "unknown"
end
