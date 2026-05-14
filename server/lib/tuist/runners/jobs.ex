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
  """

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Runners.Job

  require Logger

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
    Job
    |> from(hints: ["FINAL"])
    |> where([j], j.fleet_name == ^fleet_name and j.status == "queued")
    |> exclude_accounts(ineligible_account_ids)
    |> order_by([j], asc: j.enqueued_at, asc: j.workflow_job_id)
    |> limit(1)
    |> select([j], %{
      workflow_job_id: j.workflow_job_id,
      account_id: j.account_id,
      fleet_name: j.fleet_name,
      repo: j.repo,
      workflow_run_id: j.workflow_run_id,
      run_attempt: j.run_attempt,
      job_name: j.job_name,
      head_branch: j.head_branch,
      head_sha: j.head_sha,
      enqueued_at: j.enqueued_at
    })
    |> ClickHouseRepo.one()
    |> case do
      nil -> {:error, :empty}
      candidate -> {:ok, candidate}
    end
  end

  defp exclude_accounts(query, []), do: query

  defp exclude_accounts(query, account_ids) when is_list(account_ids) do
    where(query, [j], j.account_id not in ^account_ids)
  end

  @doc """
  Records the `claimed` state transition for customer visibility.
  Called after `Claims.attempt/4` succeeds and we're about to mint.
  """
  def record_claimed(candidate, pod_name, claimed_at) when is_map(candidate) and is_binary(pod_name) do
    now = DateTime.utc_now()

    row = Map.merge(candidate, %{status: "claimed", claimed_at: claimed_at, pod_name: pod_name, updated_at: now})

    insert_row!(row)
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
  value. Uses RMT `FINAL` so we read the merged latest state per
  workflow_job_id (no double-counting of jobs that have since
  transitioned out of `queued`).
  """
  def queued_count_by_fleet(fleet_name) when is_binary(fleet_name) do
    Job
    |> from(hints: ["FINAL"])
    |> where([j], j.fleet_name == ^fleet_name and j.status == "queued")
    |> select([j], count(j.workflow_job_id))
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
        SELECT claimed_at, completed_at
        FROM runner_jobs FINAL
        WHERE fleet_name = {fleet:String}
          AND claimed_at >= now() - toIntervalHour(2)
          AND claimed_at != toDateTime64('1970-01-01 00:00:00.000', 6, 'UTC')
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
    Job
    |> from(hints: ["FINAL"])
    |> where([j], j.account_id == ^account_id)
    |> group_by([j], j.status)
    |> select([j], {j.status, count(j.workflow_job_id)})
    |> ClickHouseRepo.all()
    |> Map.new()
  end

  # ----- internal -----

  # Fetch the merged current state of a workflow_job. The RMT
  # FINAL hint forces ClickHouse to apply the merge at query time
  # so we see the latest `updated_at` row even before the
  # background merge has run.
  defp current(workflow_job_id) do
    Job
    |> from(hints: ["FINAL"])
    |> where([j], j.workflow_job_id == ^workflow_job_id)
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

  defp epoch, do: ~U[1970-01-01 00:00:00.000000Z]
end
