defmodule Tuist.Runners.Jobs do
  @moduledoc """
  Lifecycle API over `runner_jobs` (ClickHouse). One logical row
  per workflow_job; state transitions are INSERTs that advance the
  RMT version column (`updated_at`). The merge keeps the row with
  the latest `updated_at` for each `workflow_job_id`.

  ## Why ClickHouse and not Postgres

  We use ClickHouse heavily across the codebase already; co-locating
  the runner-jobs lifecycle there avoids a Postgres dependency on the
  hot dispatch path. The customer-facing surfaces ("queued",
  "running", "recent runs") read from this table directly.

  The trade-off is the loss of OLTP primitives — no row locks, no
  unique constraints, no transactional UPDATE. We work around each:

    * **Claim atomicity** → `claim/3` is "INSERT then verify by
      reading back" with a deterministic tiebreaker on
      `(updated_at DESC, pod_name ASC)`. Two racing claims compute
      the same winner from any vantage point, so the loser silently
      bails before any JIT mint / runner registration. Worst case
      is one extra ClickHouse query per claim; no double-dispatch.

    * **Per-account cap** → counted via `argMax` aggregation in the
      same query that picks the next eligible workflow_job. No
      separate K8s LIST in the hot path.

    * **Webhook idempotency** → GitHub retries of
      `workflow_job.queued` INSERT another row with the same
      `workflow_job_id`. RMT merge collapses them; the state is
      still `queued` so the merge is a no-op visible to clients.

    * **Recovery from server crash mid-mint** → `StaleClaimsWorker`
      finds rows stuck in `claimed` past the threshold and INSERTs
      a fresh row with `status='queued'`, advancing `updated_at`.

  ## State machine

      queued → claimed → running → completed

  Each transition is an INSERT carrying ALL columns forward from
  the previous state plus the updated fields — RMT merges on
  `(workflow_job_id)` keeping the latest `updated_at`, so columns
  not refreshed by the new INSERT would otherwise revert.
  """

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Runners.Job

  require Logger

  # Read-after-write visibility for the verify-readback. Today
  # this is a no-op: Tuist's deployed ClickHouse runs as a
  # single-replica StatefulSet with plain `MergeTree` /
  # `ReplacingMergeTree` (not `Replicated*MergeTree`), so a
  # synchronous `IngestRepo.insert_all/2` returns only after the
  # row is written to the part, and the very next SELECT to the
  # same node sees it. No replication, no lag.
  #
  # If we ever shard the runners-jobs table or move ClickHouse to
  # a multi-replica replicated setup, the right primitives are:
  #
  #   * `insert_quorum_parallel = 0` + `insert_quorum = N` on the
  #     INSERT so it waits for N replicas to ack.
  #   * `select_sequential_consistency = 1` on the SELECT so the
  #     read replica waits for the latest quorum-committed write.
  #
  # That would replace the assumption below with an actual ClickHouse
  # linearisability guarantee. Until then we don't pay an extra ms
  # of latency on every claim.


  @doc """
  Idempotent enqueue. Inserts a `status='queued'` row for the
  workflow_job. Re-runs with the same `workflow_job_id` are
  collapsed by RMT merge — the latest `updated_at` wins, but
  since both INSERTs carry the same `queued` state, the merge
  is a no-op visible to clients.

  Returns `:ok` on success.
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
  Picks the oldest eligible workflow_job on `fleet_name`, INSERTs a
  `claimed` transition for it, then reads back to determine the
  winner via the deterministic tiebreaker.

  `cap_lookup` maps
  `account_id => %{cap: max_concurrent, inflight: current_count}`
  for every account observed in-flight on the fleet (built by the
  caller from a single `counts_per_account/1` query + an
  `accounts` join so the cap check uses one consistent snapshot).
  Accounts not present in the map are treated as 0 in-flight,
  cap unrestricted.

  Returns:
    * `{:ok, %Job{}}` — we won the claim. Caller proceeds with
      JIT mint + `start/2` transition.
    * `{:error, :empty}` — no eligible workflow_job on this fleet.
    * `{:error, :over_cap}` — the picked candidate's account was
      over-cap once the cap check ran.
    * `{:error, :lost_race}` — we inserted but another poll's
      INSERT won the readback. Caller bails cleanly (no mint, no
      Pod label, no runner registration).
  """
  def claim(fleet_name, pod_name, cap_lookup) when is_binary(fleet_name) and is_binary(pod_name) and is_map(cap_lookup) do
    case pick_candidate(fleet_name, cap_lookup) do
      {:error, _reason} = err ->
        err

      {:ok, candidate} ->
        attempt_claim(candidate, pod_name)
    end
  end

  defp attempt_claim(candidate, pod_name) do
    now = DateTime.utc_now()

    row = Map.merge(candidate, %{status: "claimed", claimed_at: now, pod_name: pod_name, updated_at: now})

    insert_row!(row)

    case current_state(candidate.workflow_job_id) do
      %Job{status: "claimed", pod_name: ^pod_name} = job ->
        {:ok, job}

      %Job{status: "claimed", pod_name: other_pod} ->
        Logger.info("runners: lost claim race",
          workflow_job_id: candidate.workflow_job_id,
          ours: pod_name,
          winner: other_pod
        )

        {:error, :lost_race}

      %Job{status: status} ->
        # Job moved past `claimed` between our INSERT and readback
        # (e.g., a stale-claims worker rolled it back). Treat as
        # lost — caller polls again.
        Logger.info("runners: claim raced with state transition",
          workflow_job_id: candidate.workflow_job_id,
          observed_status: status
        )

        {:error, :lost_race}

      nil ->
        # Readback returned no row. Shouldn't happen — we just
        # inserted. Treat as lost so we don't proceed without
        # confirmation.
        {:error, :lost_race}
    end
  end

  @doc """
  Transitions a claimed job to `running` and records the bound
  runner name. Called after the JIT mint succeeds.
  """
  def start(%Job{} = job, runner_name) when is_binary(runner_name) do
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

  @doc """
  Releases a claim back to `queued`. Called when the mint fails or
  the post-claim path errors out. Uses the captured `claimed_at`
  as a guard — if the row's claimed_at has moved past ours (the
  stale-claims worker won the race and a different poll
  re-claimed), the release silently no-ops.
  """
  def release(%Job{claimed_at: handle} = job) do
    case current_state(job.workflow_job_id) do
      %Job{claimed_at: ^handle, status: "claimed"} ->
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

      _other ->
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
  yet (e.g. a delivery race where `completed` arrives before
  `queued`).
  """
  def complete(workflow_job_id, conclusion) when is_integer(workflow_job_id) and is_binary(conclusion) do
    case current_state(workflow_job_id) do
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
        {:ok, Map.merge(job, %{status: "completed", conclusion: conclusion, completed_at: now, updated_at: now})}
    end
  end

  @doc """
  Counts active (`claimed` or `running`) jobs per account on
  `fleet_name`. Returns `%{account_id => count}`. Used by the
  caller to build the cap_lookup for `claim/3`.
  """
  def counts_per_account(fleet_name) when is_binary(fleet_name) do
    sql = """
    SELECT account_id, count() AS cnt
    FROM runner_jobs FINAL
    WHERE fleet_name = {fleet_name:String}
      AND status IN ('claimed', 'running')
    GROUP BY account_id
    """

    case ClickHouseRepo.query(sql, %{"fleet_name" => fleet_name}) do
      {:ok, %{rows: rows}} ->
        Map.new(rows, fn [account_id, cnt] -> {account_id, cnt} end)

      {:error, reason} ->
        Logger.warning("runners: counts_per_account failed; defaulting to empty",
          reason: inspect(reason)
        )

        %{}
    end
  end

  @doc """
  Returns rows whose `status='claimed'` AND `claimed_at` is older
  than `threshold`. Caller (the StaleClaimsWorker) re-INSERTs each
  with `status='queued'` to roll the row back.
  """
  def stale_claimed(threshold) do
    sql = """
    SELECT *
    FROM runner_jobs FINAL
    WHERE status = 'claimed' AND claimed_at < {threshold:DateTime64(6,'UTC')}
    """

    case ClickHouseRepo.query(sql, %{"threshold" => threshold}) do
      {:ok, %{rows: rows, columns: columns}} ->
        Enum.map(rows, &row_to_job(columns, &1))

      {:error, reason} ->
        Logger.warning("runners: stale_claimed query failed",
          reason: inspect(reason)
        )

        []
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

  # Picks the oldest queued workflow_job whose account is below
  # its cap. Returns a map suitable for INSERTing as the next
  # state transition.
  defp pick_candidate(fleet_name, cap_lookup) do
    ineligible =
      cap_lookup
      |> Enum.filter(fn {_account_id, %{cap: cap, inflight: in_use}} -> in_use >= cap end)
      |> Enum.map(fn {account_id, _} -> account_id end)

    # Deterministic ordering — `(enqueued_at ASC, workflow_job_id ASC)` —
    # means two concurrent pollers see the SAME row as the next
    # candidate. Their racing INSERTs then collapse on the claim
    # tiebreaker in `attempt_claim`'s verify-readback rather than
    # over-claiming two distinct workflow_jobs for the same
    # account. The pair-uniqueness of `workflow_job_id` makes the
    # tiebreaker total.
    sql = """
    SELECT
      workflow_job_id, account_id, fleet_name, repo,
      workflow_run_id, run_attempt, job_name, head_branch, head_sha,
      enqueued_at
    FROM runner_jobs FINAL
    WHERE fleet_name = {fleet_name:String}
      AND status = 'queued'
      #{if ineligible == [], do: "", else: "AND account_id NOT IN {ineligible:Array(Int64)}"}
    ORDER BY enqueued_at ASC, workflow_job_id ASC
    LIMIT 1
    """

    params =
      if ineligible == [],
        do: %{"fleet_name" => fleet_name},
        else: %{"fleet_name" => fleet_name, "ineligible" => ineligible}

    case ClickHouseRepo.query(sql, params) do
      {:ok, %{rows: []}} ->
        {:error, :empty}

      {:ok, %{rows: [row], columns: cols}} ->
        {:ok, row_to_map(cols, row)}

      {:error, reason} ->
        Logger.warning("runners: pick_candidate failed",
          reason: inspect(reason),
          fleet: fleet_name
        )

        {:error, :empty}
    end
  end

  defp current_state(workflow_job_id) do
    sql = """
    SELECT *
    FROM runner_jobs FINAL
    WHERE workflow_job_id = {workflow_job_id:Int64}
    ORDER BY updated_at DESC, pod_name ASC
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
