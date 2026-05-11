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
    sql = """
    SELECT
      workflow_job_id, account_id, fleet_name, repo,
      workflow_run_id, run_attempt, job_name, head_branch, head_sha,
      enqueued_at
    FROM runner_jobs FINAL
    WHERE fleet_name = {fleet_name:String}
      AND status = 'queued'
      #{if ineligible_account_ids == [], do: "", else: "AND account_id NOT IN {ineligible:Array(Int64)}"}
    ORDER BY enqueued_at ASC, workflow_job_id ASC
    LIMIT 1
    """

    params =
      if ineligible_account_ids == [],
        do: %{"fleet_name" => fleet_name},
        else: %{"fleet_name" => fleet_name, "ineligible" => ineligible_account_ids}

    case ClickHouseRepo.query(sql, params) do
      {:ok, %{rows: []}} ->
        {:error, :empty}

      {:ok, %{rows: [row], columns: cols}} ->
        {:ok, row_to_map(cols, row)}

      {:error, reason} ->
        Logger.warning("runners: pick_queued failed",
          reason: inspect(reason),
          fleet: fleet_name
        )

        {:error, :empty}
    end
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
  Counts jobs in each lifecycle state for an account. Useful for
  customer dashboards.
  """
  def status_counts(account_id) when is_integer(account_id) do
    sql = """
    SELECT status, count() AS cnt
    FROM runner_jobs FINAL
    WHERE account_id = {account_id:Int64}
    GROUP BY status
    """

    case ClickHouseRepo.query(sql, %{"account_id" => account_id}) do
      {:ok, %{rows: rows}} ->
        Map.new(rows, fn [status, cnt] -> {status, cnt} end)

      {:error, _reason} ->
        %{}
    end
  end

  # ----- internal -----

  defp current(workflow_job_id) do
    sql = """
    SELECT *
    FROM runner_jobs FINAL
    WHERE workflow_job_id = {workflow_job_id:Int64}
    LIMIT 1
    """

    case ClickHouseRepo.query(sql, %{"workflow_job_id" => workflow_job_id}) do
      {:ok, %{rows: []}} -> nil
      {:ok, %{rows: [row], columns: cols}} -> row_to_job(cols, row)
      {:error, _} -> nil
    end
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

  defp row_to_map(columns, row) do
    columns
    |> Enum.zip(row)
    |> Map.new(fn {col, val} -> {String.to_existing_atom(col), val} end)
  end

  defp row_to_job(columns, row) do
    fields = row_to_map(columns, row)
    struct(Job, fields)
  end

  defp epoch, do: ~U[1970-01-01 00:00:00.000000Z]
end
