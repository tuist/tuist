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

    broadcast_status_change(Map.get(attrs, :account_id), "queued")
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
      workflow_name: j.workflow_name,
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

    :telemetry.execute(
      Telemetry.event_name_job_claim(),
      %{count: 1, queue_time_ms: duration_ms(candidate[:enqueued_at], claimed_at)},
      %{fleet: Map.get(candidate, :fleet_name, ""), outcome: "ok"}
    )

    broadcast_status_change(Map.get(candidate, :account_id), "claimed")
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

        broadcast_status_change(job.account_id, "running")
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

        broadcast_status_change(job.account_id, "queued")
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

        broadcast_status_change(job.account_id, "completed")

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
  Lists jobs for an account, ordered so the most recently updated
  rows come first. Used by the customer-facing Jobs dashboard.

  Options:
    * `:limit` — page size, default 50
    * `:offset` — number of rows to skip (page-based pagination)
    * `:status` — restrict to one of `"queued" | "claimed" | "running" | "completed"`
    * `:conclusion` — restrict completed jobs to a conclusion
      (e.g. `"success" | "failure" | "cancelled" | "skipped"`)
    * `:repo` — substring match on `repo`
    * `:workflow_name` — substring match on `workflow_name`
    * `:job_name` — substring match on `job_name`
    * `:head_branch` — substring match on `head_branch`

  RMT `FINAL` is used so callers see the merged latest-state row
  per workflow_job even before background merges run.
  """
  def list_for_account(account_id, opts \\ []) when is_integer(account_id) and is_list(opts) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    account_id
    |> filtered_jobs_query(opts)
    |> order_by([j], desc: j.updated_at, desc: j.workflow_job_id)
    |> limit(^limit)
    |> offset(^offset)
    |> ClickHouseRepo.all()
  end

  @doc """
  Total count of jobs matching the same filters used by
  `list_for_account/2`. Used to drive pagination.
  """
  def count_for_account(account_id, opts \\ []) when is_integer(account_id) and is_list(opts) do
    [%{count: count} | _] =
      account_id
      |> filtered_jobs_query(opts)
      |> select([j], %{count: count(j.workflow_job_id)})
      |> ClickHouseRepo.all()
      |> case do
        [] -> [%{count: 0}]
        rows -> rows
      end

    count || 0
  end

  defp filtered_jobs_query(account_id, opts) do
    Job
    |> from(hints: ["FINAL"])
    |> where([j], j.account_id == ^account_id)
    |> maybe_filter_status(Keyword.get(opts, :status))
    |> maybe_filter_conclusion(Keyword.get(opts, :conclusion))
    |> maybe_filter_like(:repo, Keyword.get(opts, :repo))
    |> maybe_filter_like(:workflow_name, Keyword.get(opts, :workflow_name))
    |> maybe_filter_like(:job_name, Keyword.get(opts, :job_name))
    |> maybe_filter_like(:head_branch, Keyword.get(opts, :head_branch))
  end

  defp maybe_filter_status(query, nil), do: query

  defp maybe_filter_status(query, status) when is_binary(status) do
    where(query, [j], j.status == ^status)
  end

  defp maybe_filter_conclusion(query, nil), do: query

  defp maybe_filter_conclusion(query, conclusion) when is_binary(conclusion) do
    where(query, [j], j.conclusion == ^conclusion)
  end

  defp maybe_filter_like(query, _field, nil), do: query
  defp maybe_filter_like(query, _field, ""), do: query

  defp maybe_filter_like(query, :repo, value) when is_binary(value) do
    pattern = "%#{value}%"
    where(query, [j], ilike(j.repo, ^pattern))
  end

  defp maybe_filter_like(query, :workflow_name, value) when is_binary(value) do
    pattern = "%#{value}%"
    where(query, [j], ilike(j.workflow_name, ^pattern))
  end

  defp maybe_filter_like(query, :job_name, value) when is_binary(value) do
    pattern = "%#{value}%"
    where(query, [j], ilike(j.job_name, ^pattern))
  end

  defp maybe_filter_like(query, :head_branch, value) when is_binary(value) do
    pattern = "%#{value}%"
    where(query, [j], ilike(j.head_branch, ^pattern))
  end

  @doc """
  Returns the merged current state for a single `workflow_job_id`
  belonging to `account_id`. Used by the detail page so the URL
  can't be tampered with to view another customer's run.
  """
  def get_for_account(account_id, workflow_job_id)
      when is_integer(account_id) and is_integer(workflow_job_id) do
    Job
    |> from(hints: ["FINAL"])
    |> where([j], j.account_id == ^account_id and j.workflow_job_id == ^workflow_job_id)
    |> limit(1)
    |> ClickHouseRepo.one()
    |> case do
      nil -> {:error, :not_found}
      job -> {:ok, job}
    end
  end

  @doc """
  Aggregates `runner_jobs` into per-workflow rollups for the
  customer-facing Workflows dashboard. One row per `(workflow_name,
  repo)` pair, ordered by most recently active first.

  Each row carries:

    * `:workflow_name`, `:repo`
    * `:total_jobs`
    * `:success_count`, `:failure_count`, `:cancelled_count`, `:skipped_count`
    * `:in_progress_count` — claimed + running + queued (anything not
      completed)
    * `:avg_duration_ms` — average completed job duration (epoch
      sentinel `started_at`/`completed_at` excluded)
    * `:last_run_at` — max `enqueued_at`

  Options:
    * `:limit` — page size, default 50
    * `:repo` — substring match on `repo`
    * `:workflow_name` — substring match on `workflow_name`
    * `:head_branch` — substring match on `head_branch`
  """
  def list_workflows_for_account(account_id, opts \\ []) when is_integer(account_id) and is_list(opts) do
    limit = Keyword.get(opts, :limit, 50)

    Job
    |> from(hints: ["FINAL"])
    |> where([j], j.account_id == ^account_id)
    |> maybe_filter_like(:repo, Keyword.get(opts, :repo))
    |> maybe_filter_like(:workflow_name, Keyword.get(opts, :workflow_name))
    |> maybe_filter_like(:head_branch, Keyword.get(opts, :head_branch))
    |> group_by([j], [j.workflow_name, j.repo])
    |> select([j], %{
      workflow_name: j.workflow_name,
      repo: j.repo,
      total_jobs: count(j.workflow_job_id),
      success_count:
        fragment("countIf(? = 'completed' AND ? = 'success')", j.status, j.conclusion),
      failure_count:
        fragment("countIf(? = 'completed' AND ? = 'failure')", j.status, j.conclusion),
      cancelled_count:
        fragment("countIf(? = 'completed' AND ? = 'cancelled')", j.status, j.conclusion),
      skipped_count:
        fragment("countIf(? = 'completed' AND ? = 'skipped')", j.status, j.conclusion),
      in_progress_count: fragment("countIf(? != 'completed')", j.status),
      avg_duration_ms:
        fragment(
          "avgIf((toUnixTimestamp64Milli(?) - toUnixTimestamp64Milli(?)), ? = 'completed' AND toUnixTimestamp64Milli(?) > 0 AND toUnixTimestamp64Milli(?) > 0)",
          j.completed_at,
          j.started_at,
          j.status,
          j.started_at,
          j.completed_at
        ),
      last_run_at: max(j.enqueued_at)
    })
    |> order_by([j], desc: max(j.enqueued_at))
    |> limit(^limit)
    |> ClickHouseRepo.all()
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

  @doc """
  Pub/Sub topic for an account's runner-job lifecycle events.
  Subscribers receive `{:runner_jobs_status_changed, %{status: ...}}`
  whenever any job in the account transitions, so LiveViews showing
  Running / Queued counts can refresh.
  """
  def topic(account_id) when is_integer(account_id), do: "runner_jobs:#{account_id}"

  defp broadcast_status_change(account_id, new_status) when is_integer(account_id) do
    Tuist.PubSub.broadcast(%{status: new_status}, topic(account_id), :runner_jobs_status_changed)
    :ok
  end

  defp broadcast_status_change(_, _), do: :ok
end
