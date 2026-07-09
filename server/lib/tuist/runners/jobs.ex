defmodule Tuist.Runners.Jobs do
  @moduledoc """
  ClickHouse-backed lifecycle table for workflow_jobs. The
  `runner_jobs` ReplacingMergeTree carries one logical row per
  `workflow_job_id`; every state transition is an INSERT that
  advances the version column (`updated_at`) and RMT merge keeps
  the latest row per key.

  This module is **state-recording + read-only views**. Claim
  atomicity lives in `Tuist.Runners.Claims` (a thin Postgres
  table). The split:

    * **Postgres `runner_claims`** is the OLTP claim lock. One
      row per currently-claimed workflow_job; PK on
      `workflow_job_id` gives atomic INSERT-ON-CONFLICT-DO-NOTHING.
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
  visible to clients. `workflow_job.waiting` uses `enqueue_if_missing/1`
  because GitHub can emit it while waiting for self-hosted capacity;
  it should create a missing row without regressing an already-claimed
  job back to queued.

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
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.Job
  alias Tuist.Runners.Telemetry

  require Logger

  @doc """
  Latest `enqueued_at` per `requested_dispatch_label` for an account.

  Powers the "Last used" column on the Profiles page — a profile's
  customer-facing label (`tuist-<name>`) is the key. Returns a map of
  `label => %DateTime{}`; labels with no jobs are simply absent (the
  caller renders those as "never used"). `enqueued_at` is stable
  across a workflow_job's state transitions, so `max/1` over the RMT
  rows gives the most recent job's enqueue time without needing
  `argMax`.
  """
  def last_used_at_by_dispatch_label(account_id) when is_integer(account_id) do
    from(j in Job,
      where: j.account_id == ^account_id and j.requested_dispatch_label != "",
      group_by: j.requested_dispatch_label,
      select: {j.requested_dispatch_label, max(j.enqueued_at)}
    )
    |> ClickHouseRepo.all()
    |> Map.new()
  end

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
  Enqueues a job only when no lifecycle row exists yet.

  Used for GitHub's `workflow_job.waiting` webhook, which represents a
  self-hosted job waiting for runner capacity. It fills the gap when
  GitHub does not deliver a normal `queued` event, while avoiding a
  late `waiting` delivery from moving an existing claimed/running job
  back to queued.
  """
  def enqueue_if_missing(%{workflow_job_id: workflow_job_id} = attrs) when is_integer(workflow_job_id) do
    case current(workflow_job_id) do
      nil -> enqueue(attrs)
      %Job{} -> :ok
    end
  end

  @doc """
  Picks the oldest queued candidate on `fleet_name`. The
  caller's responsibility to then atomically claim it via
  `Tuist.Runners.Claims.attempt/4`.

  `ineligible_account_ids` is an optional set of account_ids to
  exclude from candidate selection. Returns the candidate's full
  metadata so we can carry it forward on the `claimed` INSERT.

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
        repository: fragment("argMax(?, ?)", j.repository, j.updated_at),
        workflow_run_id: fragment("argMax(?, ?)", j.workflow_run_id, j.updated_at),
        workflow_name: fragment("argMax(?, ?)", j.workflow_name, j.updated_at),
        run_attempt: fragment("argMax(?, ?)", j.run_attempt, j.updated_at),
        job_name: fragment("argMax(?, ?)", j.job_name, j.updated_at),
        head_branch: fragment("argMax(?, ?)", j.head_branch, j.updated_at),
        head_sha: fragment("argMax(?, ?)", j.head_sha, j.updated_at),
        enqueued_at: fragment("argMax(?, ?)", j.enqueued_at, j.updated_at),
        requested_dispatch_label: fragment("argMax(?, ?)", j.requested_dispatch_label, j.updated_at)
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

  Does NOT open the per-Pod billing session — `Tuist.Runners`
  opens it only after `serve_claim/5` commits (JIT minted +
  `running` recorded). Opening here would leak an open session
  for every dispatch that fails between claim and JIT-mint
  (pool lookup, GH API hiccup, etc.), which `Billing` then
  clamps to the 6h max-lifetime — over-billing for compute the
  customer never received.
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
            claimed_at: nil,
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

  Per-step data lives in `runner_job_steps`; the caller writes it
  via `Tuist.Runners.JobSteps.record/1` before invoking this.
  """
  def complete(workflow_job_id, conclusion) when is_integer(workflow_job_id) and is_binary(conclusion) do
    case current(workflow_job_id) do
      nil ->
        {:error, :not_found}

      %Job{} = job ->
        now = DateTime.utc_now()

        completion = %{
          status: "completed",
          conclusion: conclusion,
          completed_at: now,
          updated_at: now
        }

        row =
          job
          |> job_to_row()
          |> Map.merge(completion)

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

        {:ok, Map.merge(job, completion)}
    end
  end

  @doc """
  Lists jobs whose log archive has aged past `threshold`. Drives the
  daily prune that keeps the S3 archive at parity with the 90-day TTL
  on `runner_job_logs`.

  Uses the `argMax(col, updated_at) GROUP BY workflow_job_id`
  pattern documented in this module's `@moduledoc` rather than
  `FINAL`. The prune scans every job — without a workflow_job_id
  scope, `FINAL`'s merge would span every part in `runner_jobs`,
  which scales poorly as the table grows.
  """
  def list_expired_archives(%DateTime{} = threshold) do
    ClickHouseRepo.all(
      from(j in Job,
        group_by: j.workflow_job_id,
        having:
          not is_nil(fragment("argMax(?, ?)", j.log_archived_at, j.updated_at)) and
            fragment("argMax(?, ?)", j.log_archived_at, j.updated_at) < ^threshold,
        select: %{workflow_job_id: j.workflow_job_id, account_id: fragment("argMax(?, ?)", j.account_id, j.updated_at)}
      )
    )
  end

  @doc """
  Stamps the job row with the time its gzipped log archive landed in
  S3 (or clears it when the archive has been pruned). State-transition
  INSERT, carrying all other columns forward.

  No-op when no row exists yet for the workflow_job.
  """
  def set_log_archived_at(workflow_job_id, archived_at)
      when is_integer(workflow_job_id) and (is_nil(archived_at) or is_struct(archived_at, DateTime)) do
    case current(workflow_job_id) do
      nil ->
        :ok

      %Job{} = job ->
        now = DateTime.utc_now()

        row =
          job
          |> job_to_row()
          |> Map.merge(%{log_archived_at: archived_at, updated_at: now})

        insert_row!(row)
        :ok
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
    * `:repository` — substring match on `repository`
    * `:workflow_name` — substring match on `workflow_name`
    * `:job_name` — substring match on `job_name`
    * `:head_branch` — substring match on `head_branch`

  Deduplicates one row per workflow_job via the
  `latest_jobs_subquery/2` GROUP BY + argMax pattern — that gives
  callers the merged latest-state row without paying `FINAL`'s
  per-read part-merge cost.
  """
  def list_for_account(account_id, opts \\ []) when is_integer(account_id) and is_list(opts) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    sort_by = Keyword.get(opts, :sort_by, "enqueued")
    sort_order = Keyword.get(opts, :sort_order, default_jobs_sort_order(sort_by))

    sub = latest_jobs_subquery(account_id, opts)

    from(j in subquery(sub), select: j)
    |> maybe_filter_status(Keyword.get(opts, :status))
    |> maybe_filter_conclusion(Keyword.get(opts, :conclusion))
    |> jobs_order_by(sort_by, sort_order)
    |> limit(^limit)
    |> offset(^offset)
    |> ClickHouseRepo.all()
  end

  # Alphabetical sorts feel natural ascending; everything else
  # (timestamps, durations) defaults to descending so the freshest
  # / longest rows land at the top.
  defp default_jobs_sort_order("job"), do: "asc"
  defp default_jobs_sort_order("workflow"), do: "asc"
  defp default_jobs_sort_order(_), do: "desc"

  defp jobs_order_by(query, "job", "asc"), do: order_by(query, [j], asc: j.job_name, desc: j.workflow_job_id)

  defp jobs_order_by(query, "job", _desc), do: order_by(query, [j], desc: j.job_name, desc: j.workflow_job_id)

  defp jobs_order_by(query, "workflow", "asc"), do: order_by(query, [j], asc: j.workflow_name, desc: j.workflow_job_id)

  defp jobs_order_by(query, "workflow", _desc), do: order_by(query, [j], desc: j.workflow_name, desc: j.workflow_job_id)

  # `duration` orders by elapsed runtime (completed_at - started_at)
  # in milliseconds. Rows without both timestamps (still queued /
  # running / claimed) coalesce to 0 so they cluster at the bottom of
  # a descending sort instead of producing nan.
  defp jobs_order_by(query, "duration", "asc") do
    order_by(query, [j],
      asc:
        fragment(
          "if(? = 'completed' AND isNotNull(?) AND isNotNull(?), toUnixTimestamp64Milli(?) - toUnixTimestamp64Milli(?), 0)",
          j.status,
          j.started_at,
          j.completed_at,
          j.completed_at,
          j.started_at
        ),
      desc: j.workflow_job_id
    )
  end

  defp jobs_order_by(query, "duration", _desc) do
    order_by(query, [j],
      desc:
        fragment(
          "if(? = 'completed' AND isNotNull(?) AND isNotNull(?), toUnixTimestamp64Milli(?) - toUnixTimestamp64Milli(?), 0)",
          j.status,
          j.started_at,
          j.completed_at,
          j.completed_at,
          j.started_at
        ),
      desc: j.workflow_job_id
    )
  end

  defp jobs_order_by(query, _enqueued_default, "asc"),
    do: order_by(query, [j], asc: j.enqueued_at, desc: j.workflow_job_id)

  defp jobs_order_by(query, _enqueued_default, _desc),
    do: order_by(query, [j], desc: j.enqueued_at, desc: j.workflow_job_id)

  @doc """
  Total count of jobs matching the same filters used by
  `list_for_account/2`. Used to drive pagination.
  """
  def count_for_account(account_id, opts \\ []) when is_integer(account_id) and is_list(opts) do
    sub = latest_jobs_subquery(account_id, opts)

    [%{count: count} | _] =
      from(j in subquery(sub), select: %{count: count(j.workflow_job_id)})
      |> maybe_filter_status(Keyword.get(opts, :status))
      |> maybe_filter_conclusion(Keyword.get(opts, :conclusion))
      |> ClickHouseRepo.all()
      |> case do
        [] -> [%{count: 0}]
        rows -> rows
      end

    count || 0
  end

  # Inner dedup subquery for every multi-row read in this module.
  # GROUP BY workflow_job_id + argMax(field, updated_at) gives us
  # one row per workflow_job carrying its latest state — the same
  # logical view `FROM … FINAL` would have produced, without the
  # per-read part-merge cost. Stable-across-versions filters
  # (repository, workflow_name, head_branch, job_name, platform, search-by-
  # job_name) sit inside the inner WHERE so we scan fewer rows;
  # latest-state filters (status, conclusion) belong on the OUTER
  # query so the deduped state is what gets matched.
  defp latest_jobs_subquery(account_id, opts) do
    Job
    |> where([j], j.account_id == ^account_id)
    |> maybe_filter_like(:repository, Keyword.get(opts, :repository))
    |> maybe_filter_like(:workflow_name, Keyword.get(opts, :workflow_name))
    |> maybe_filter_like(:job_name, Keyword.get(opts, :job_name))
    |> maybe_filter_like(:head_branch, Keyword.get(opts, :head_branch))
    |> maybe_filter_platform(Keyword.get(opts, :platform))
    |> maybe_filter_search(Keyword.get(opts, :search))
    |> group_by([j], j.workflow_job_id)
    |> select([j], %{
      workflow_job_id: j.workflow_job_id,
      account_id: fragment("argMax(?, ?)", j.account_id, j.updated_at),
      fleet_name: fragment("argMax(?, ?)", j.fleet_name, j.updated_at),
      repository: fragment("argMax(?, ?)", j.repository, j.updated_at),
      workflow_run_id: fragment("argMax(?, ?)", j.workflow_run_id, j.updated_at),
      workflow_name: fragment("argMax(?, ?)", j.workflow_name, j.updated_at),
      run_attempt: fragment("argMax(?, ?)", j.run_attempt, j.updated_at),
      job_name: fragment("argMax(?, ?)", j.job_name, j.updated_at),
      head_branch: fragment("argMax(?, ?)", j.head_branch, j.updated_at),
      head_sha: fragment("argMax(?, ?)", j.head_sha, j.updated_at),
      status: fragment("argMax(?, ?)", j.status, j.updated_at),
      conclusion: fragment("argMax(?, ?)", j.conclusion, j.updated_at),
      enqueued_at: fragment("argMax(?, ?)", j.enqueued_at, j.updated_at),
      claimed_at: fragment("argMax(?, ?)", j.claimed_at, j.updated_at),
      started_at: fragment("argMax(?, ?)", j.started_at, j.updated_at),
      completed_at: fragment("argMax(?, ?)", j.completed_at, j.updated_at),
      pod_name: fragment("argMax(?, ?)", j.pod_name, j.updated_at),
      runner_name: fragment("argMax(?, ?)", j.runner_name, j.updated_at),
      updated_at: max(j.updated_at)
    })
  end

  # Search input is scoped to `job_name`. Workflow filtering happens
  # through the dedicated Workflow filter chip.
  defp maybe_filter_search(query, nil), do: query
  defp maybe_filter_search(query, ""), do: query

  defp maybe_filter_search(query, value) when is_binary(value) do
    pattern = "%#{value}%"
    where(query, [j], ilike(j.job_name, ^pattern))
  end

  # Platform filter narrows on the `fleet_name` prefix. Each
  # platform's `Catalog.fleet_name_prefixes/1` returns both the legacy
  # `<platform>-…` per-env pool prefix and the catalog-derived
  # `<runners_<platform>_pool_name_prefix>-…` prefix (e.g.
  # `tuist-runner-pool-linux-4vcpu-16gb`, `tuist-runner-pool-macos-26-5`),
  # so the dropdown matches profile-dispatched and legacy jobs together.
  defp maybe_filter_platform(query, nil), do: query
  defp maybe_filter_platform(query, ""), do: query
  defp maybe_filter_platform(query, "any"), do: query

  defp maybe_filter_platform(query, "linux"), do: filter_by_prefixes(query, Catalog.fleet_name_prefixes(:linux))

  defp maybe_filter_platform(query, "macos"), do: filter_by_prefixes(query, Catalog.fleet_name_prefixes(:macos))

  defp maybe_filter_platform(query, _), do: query

  # OR `startsWith(fleet_name, prefix)` across every prefix as a
  # single `where` clause. `or_where` would OR against the *whole*
  # prior chain (account scope and other filters), wiping them out;
  # the dynamic stays nested inside the surrounding ANDs.
  defp filter_by_prefixes(query, [first | rest]) do
    predicate =
      Enum.reduce(rest, dynamic([j], fragment("startsWith(?, ?)", j.fleet_name, ^first)), fn prefix, acc ->
        dynamic([j], ^acc or fragment("startsWith(?, ?)", j.fleet_name, ^prefix))
      end)

    where(query, ^predicate)
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

  defp maybe_filter_like(query, :repository, value) when is_binary(value) do
    pattern = "%#{value}%"
    where(query, [j], ilike(j.repository, ^pattern))
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
  def get_for_account(account_id, workflow_job_id) when is_integer(account_id) and is_integer(workflow_job_id) do
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
  flight carry `completed_at IS NULL`, so the interval check
  matches on `completed_at > bucket OR completed_at IS NULL`. The
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
          AND (j.completed_at > b.bucket OR j.completed_at IS NULL)
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
          AND claimed_at IS NOT NULL
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
  Aggregates `runner_jobs` into per-workflow rollups for the
  customer-facing Workflows dashboard. One row per `(workflow_name,
  repository)` pair, ordered by most recently active first.

  Each row carries:

    * `:workflow_name`, `:repository`
    * `:total_jobs`
    * `:success_count`, `:failure_count`, `:cancelled_count`, `:skipped_count`
    * `:in_progress_count` — claimed + running + queued (anything not
      completed)
    * `:avg_duration_ms` — average completed job duration (NULL
      `started_at`/`completed_at` excluded)
    * `:last_run_at` — max `enqueued_at`

  Options:
    * `:limit` — page size, default 50
    * `:repository` — substring match on `repository`
    * `:workflow_name` — substring match on `workflow_name`
    * `:head_branch` — substring match on `head_branch`
  """
  def list_workflows_for_account(account_id, opts \\ []) when is_integer(account_id) and is_list(opts) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    sort_by = Keyword.get(opts, :sort_by, "workflow")
    sort_order = Keyword.get(opts, :sort_order, default_sort_order(sort_by))

    sub = latest_jobs_subquery(account_id, opts)

    from(j in subquery(sub),
      group_by: [j.workflow_name, j.repository],
      select: %{
        workflow_name: j.workflow_name,
        repository: j.repository,
        total_jobs: count(j.workflow_job_id),
        success_count: fragment("countIf(? = 'completed' AND ? = 'success')", j.status, j.conclusion),
        failure_count: fragment("countIf(? = 'completed' AND ? = 'failure')", j.status, j.conclusion),
        cancelled_count: fragment("countIf(? = 'completed' AND ? = 'cancelled')", j.status, j.conclusion),
        skipped_count: fragment("countIf(? = 'completed' AND ? = 'skipped')", j.status, j.conclusion),
        in_progress_count: fragment("countIf(? != 'completed')", j.status),
        avg_duration_ms:
          fragment(
            "avgIf((toUnixTimestamp64Milli(?) - toUnixTimestamp64Milli(?)), ? = 'completed' AND isNotNull(?) AND isNotNull(?))",
            j.completed_at,
            j.started_at,
            j.status,
            j.started_at,
            j.completed_at
          ),
        last_run_at: max(j.enqueued_at)
      }
    )
    |> workflows_order_by(sort_by, sort_order)
    |> limit(^limit)
    |> offset(^offset)
    |> ClickHouseRepo.all()
  end

  # Numerical sorts default to descending (largest first feels right
  # for counts/rates); the alphabetical workflow sort defaults to
  # ascending. Callers presenting a column-header click UI should
  # mirror the same defaults so a first click matches what an
  # unscoped query returns.
  defp default_sort_order("workflow"), do: "asc"
  defp default_sort_order(_), do: "desc"

  # Each branch builds the ORDER BY for one (column, direction) pair.
  # "success_rate" divides the success countIf by the total count
  # with nullIf on the denominator so all-zero workflows don't blow
  # up with a 0/0 nan that breaks the comparator.
  defp workflows_order_by(query, "success_rate", "asc") do
    order_by(query, [j],
      asc:
        fragment(
          "coalesce(toFloat64(countIf(? = 'completed' AND ? = 'success')) / nullIf(toFloat64(count(?)), 0), 0)",
          j.status,
          j.conclusion,
          j.workflow_job_id
        ),
      desc: max(j.enqueued_at)
    )
  end

  defp workflows_order_by(query, "success_rate", _desc) do
    order_by(query, [j],
      desc:
        fragment(
          "coalesce(toFloat64(countIf(? = 'completed' AND ? = 'success')) / nullIf(toFloat64(count(?)), 0), 0)",
          j.status,
          j.conclusion,
          j.workflow_job_id
        ),
      desc: max(j.enqueued_at)
    )
  end

  defp workflows_order_by(query, "jobs", "asc") do
    order_by(query, [j], asc: count(j.workflow_job_id), desc: max(j.enqueued_at))
  end

  defp workflows_order_by(query, "jobs", _desc) do
    order_by(query, [j], desc: count(j.workflow_job_id), desc: max(j.enqueued_at))
  end

  # "avg_duration" mirrors the avg_duration_ms select fragment so the
  # ORDER BY uses the same conditional average — workflows without
  # any completed runs collapse to 0 instead of nan and land at the
  # bottom of the descending list.
  defp workflows_order_by(query, "avg_duration", "asc") do
    order_by(query, [j],
      asc:
        fragment(
          "coalesce(avgIf((toUnixTimestamp64Milli(?) - toUnixTimestamp64Milli(?)), ? = 'completed' AND isNotNull(?) AND isNotNull(?)), 0)",
          j.completed_at,
          j.started_at,
          j.status,
          j.started_at,
          j.completed_at
        ),
      desc: max(j.enqueued_at)
    )
  end

  defp workflows_order_by(query, "avg_duration", _desc) do
    order_by(query, [j],
      desc:
        fragment(
          "coalesce(avgIf((toUnixTimestamp64Milli(?) - toUnixTimestamp64Milli(?)), ? = 'completed' AND isNotNull(?) AND isNotNull(?)), 0)",
          j.completed_at,
          j.started_at,
          j.status,
          j.started_at,
          j.completed_at
        ),
      desc: max(j.enqueued_at)
    )
  end

  defp workflows_order_by(query, _workflow_default, "desc") do
    order_by(query, [j], desc: j.workflow_name, desc: j.repository)
  end

  defp workflows_order_by(query, _workflow_default, _asc) do
    order_by(query, [j], asc: j.workflow_name, asc: j.repository)
  end

  @doc """
  Returns the N most recently completed workflow_runs for the account,
  one row per `workflow_run_id`. Each row collapses the workflow_run's
  jobs into a single rollup: max(completed_at)-min(started_at) for
  duration, argMax over the latest job for human-readable fields
  (workflow_name, repository, head_branch, head_sha), and the worst
  conclusion across all the completed jobs as the run's conclusion.

  Options:
    * `:limit` — page size, default 5
    * `:repository` — exact match on `repository`
    * `:workflow_name` — exact match on `workflow_name`
  """
  def list_recent_workflow_runs_for_account(account_id, opts \\ []) when is_integer(account_id) do
    limit = Keyword.get(opts, :limit, 5)
    repository = Keyword.get(opts, :repository)
    workflow_name = Keyword.get(opts, :workflow_name)

    # Two-stage aggregation: inner dedupes to one row per
    # workflow_job (GROUP BY workflow_job_id + argMax), then the
    # outer groups those by workflow_run_id for the run-level
    # rollup. Uses exact `==` matching on repository/workflow_name —
    # distinct from the substring-search variant in
    # `latest_jobs_subquery` (ILIKE) — so we keep the inner
    # specialised rather than routing through that helper.
    inner =
      Job
      |> where([j], j.account_id == ^account_id and j.workflow_run_id > 0)
      |> maybe_eq_workflow(repository, workflow_name)
      |> maybe_filter_platform(Keyword.get(opts, :platform))
      |> group_by([j], j.workflow_job_id)
      |> select([j], %{
        workflow_job_id: j.workflow_job_id,
        workflow_run_id: fragment("argMax(?, ?)", j.workflow_run_id, j.updated_at),
        workflow_name: fragment("argMax(?, ?)", j.workflow_name, j.updated_at),
        repository: fragment("argMax(?, ?)", j.repository, j.updated_at),
        head_branch: fragment("argMax(?, ?)", j.head_branch, j.updated_at),
        head_sha: fragment("argMax(?, ?)", j.head_sha, j.updated_at),
        status: fragment("argMax(?, ?)", j.status, j.updated_at),
        conclusion: fragment("argMax(?, ?)", j.conclusion, j.updated_at),
        started_at: fragment("argMax(?, ?)", j.started_at, j.updated_at),
        completed_at: fragment("argMax(?, ?)", j.completed_at, j.updated_at),
        updated_at: max(j.updated_at)
      })

    ClickHouseRepo.all(
      from(j in subquery(inner),
        group_by: j.workflow_run_id,
        having: fragment("countIf(? != 'completed')", j.status) == 0,
        select: %{
          workflow_run_id: j.workflow_run_id,
          workflow_name: fragment("argMax(?, ?)", j.workflow_name, j.updated_at),
          repository: fragment("argMax(?, ?)", j.repository, j.updated_at),
          head_branch: fragment("argMax(?, ?)", j.head_branch, j.updated_at),
          head_sha: fragment("argMax(?, ?)", j.head_sha, j.updated_at),
          duration_ms:
            fragment(
              "maxIf(toUnixTimestamp64Milli(?), isNotNull(?)) - minIf(toUnixTimestamp64Milli(?), isNotNull(?))",
              j.completed_at,
              j.completed_at,
              j.started_at,
              j.started_at
            ),
          conclusion:
            fragment(
              "if(countIf(? = 'failure') > 0, 'failure', if(countIf(? = 'cancelled') > 0, 'cancelled', if(countIf(? = 'success') > 0, 'success', 'skipped')))",
              j.conclusion,
              j.conclusion,
              j.conclusion
            ),
          updated_at: max(j.updated_at)
        },
        order_by: [desc: max(j.updated_at)],
        limit: ^limit
      )
    )
  end

  defp maybe_eq_workflow(query, nil, nil), do: query

  defp maybe_eq_workflow(query, repository, nil) when is_binary(repository) and repository != "",
    do: where(query, [j], j.repository == ^repository)

  defp maybe_eq_workflow(query, nil, workflow_name) when is_binary(workflow_name) and workflow_name != "",
    do: where(query, [j], j.workflow_name == ^workflow_name)

  defp maybe_eq_workflow(query, repository, workflow_name)
       when is_binary(repository) and is_binary(workflow_name) and repository != "" and workflow_name != "",
       do: where(query, [j], j.repository == ^repository and j.workflow_name == ^workflow_name)

  defp maybe_eq_workflow(query, _repository, _workflow_name), do: query

  @doc """
  Lists the distinct repositories the account has dispatched jobs to
  in the last 30 days, in alphabetical order. Powers the page-level
  repository dropdown on the Workflows page — a curated list of
  values is friendlier than a free-text filter, and the 30-day
  window keeps the list short on accounts with long-tail repos.
  """
  def distinct_repositories_for_account(account_id) when is_integer(account_id) do
    thirty_days_ago = DateTime.add(DateTime.utc_now(), -30, :day)

    Job
    |> from(hints: ["FINAL"])
    |> where(
      [j],
      j.account_id == ^account_id and j.repository != "" and j.enqueued_at >= ^thirty_days_ago
    )
    |> distinct(true)
    |> order_by([j], asc: j.repository)
    |> select([j], j.repository)
    |> ClickHouseRepo.all()
  end

  @doc """
  Counts the distinct `(workflow_name, repository)` pairs that match the
  same filters used by `list_workflows_for_account/2`. Wraps the
  filtered group-by in a subquery so the outer `count()` returns one
  row per workflow pair without re-aggregating.
  """
  def count_workflows_for_account(account_id, opts \\ []) when is_integer(account_id) and is_list(opts) do
    # Route through `latest_jobs_subquery` so this count matches
    # `list_workflows_for_account/2` exactly — both share the same
    # GROUP BY + argMax dedup pass over `runner_jobs`, avoiding the
    # per-read merge cost of `FROM runner_jobs FINAL` while still
    # collapsing state-transition rows down to one row per
    # workflow_job before the (workflow_name, repository) GROUP BY.
    sub = latest_jobs_subquery(account_id, opts)

    inner =
      from(j in subquery(sub),
        group_by: [j.workflow_name, j.repository],
        select: %{workflow_name: j.workflow_name, repository: j.repository}
      )

    from(s in subquery(inner), select: count())
    |> ClickHouseRepo.one()
    |> Kernel.||(0)
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
  (`repository` for the GH API call, `claimed_at` for the PG release
  handle), so the worker doesn't need a second round trip.
  """
  def list_orphaned_running(%DateTime{} = threshold) do
    Job
    |> from(hints: ["FINAL"])
    |> where([j], j.status == "running" and j.started_at < ^threshold)
    |> select([j], %{
      workflow_job_id: j.workflow_job_id,
      account_id: j.account_id,
      repository: j.repository,
      claimed_at: j.claimed_at,
      started_at: j.started_at,
      pod_name: j.pod_name
    })
    |> ClickHouseRepo.all()
  end

  @doc """
  Lists `runner_jobs` rows whose latest state is `queued` and whose
  `enqueued_at` falls in `[enqueued_after, enqueued_before)` —
  candidates for the "queued but never reconciled" recovery path that
  `StaleQueuedJobsWorker` drives.

  A queued row only ever leaves the queue by a Pod claiming it
  (`queued → claimed → running → completed`) or a
  `workflow_job.completed` webhook marking it `completed`. When no
  runner ever registers to accept the job AND no completion webhook
  arrives (GitHub kept it `queued` on its side, or the delivery was
  lost past the redelivery window), nothing terminates the row:
  `StaleClaimsWorker` only sees PG `claimed` rows and
  `OrphanedRunnersWorker` only sees CH `running` rows, so neither
  covers `queued`.

  Both bounds are on `enqueued_at`, which `runner_jobs` is partitioned
  by and which is stable across a workflow_job's state transitions.
  `enqueued_before` drops jobs queued too recently to be stale; the
  `enqueued_after` floor bounds the scan to a finite window so the
  `argMax` dedup never has to aggregate the table's full history
  (partition pruning skips everything older). The caller sets the floor
  comfortably beyond the backstop age, so a stuck job is always reaped
  while still inside the window.

  Returns the fields the worker needs to address GitHub's Actions
  jobs API (`repository`) and to apply the hard backstop
  (`enqueued_at`).
  """
  def list_stale_queued(%DateTime{} = enqueued_after, %DateTime{} = enqueued_before) do
    ClickHouseRepo.all(
      from(j in Job,
        where: j.enqueued_at > ^enqueued_after and j.enqueued_at < ^enqueued_before,
        group_by: j.workflow_job_id,
        having: fragment("argMax(?, ?) = ?", j.status, j.updated_at, "queued"),
        select: %{
          workflow_job_id: j.workflow_job_id,
          account_id: fragment("argMax(?, ?)", j.account_id, j.updated_at),
          repository: fragment("argMax(?, ?)", j.repository, j.updated_at),
          enqueued_at: fragment("argMax(?, ?)", j.enqueued_at, j.updated_at)
        }
      )
    )
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

  # Returns `nil` when either bound is missing or the interval is
  # negative so the histogram bucketer drops the sample instead of
  # recording a garbage duration.
  defp duration_ms(%DateTime{} = from, %DateTime{} = to) do
    if DateTime.after?(to, from), do: DateTime.diff(to, from, :millisecond)
  end

  defp duration_ms(_, _), do: nil

  # Normalise GH conclusion strings into the bounded tag set the
  # dashboard groups by. `nil` and `""` collapse to `"unknown"`
  # so the conclusion-by-rate panel doesn't grow a phantom empty
  # series for in-flight rows that crash through the orphan
  # recovery path.
  defp normalise_conclusion(c) when c in [nil, ""], do: "unknown"
  defp normalise_conclusion(c) when is_binary(c), do: c

  @doc """
  Pub/Sub topic for an account's runner-job lifecycle events.
  Subscribers receive `{:runner_jobs_status_changed, %{status: ...}}`
  whenever any job in the account transitions — used by callers
  that need to refresh Running / Queued aggregates in real time.
  """
  def topic(account_id) when is_integer(account_id), do: "runner_jobs:#{account_id}"

  defp broadcast_status_change(account_id, new_status) when is_integer(account_id) do
    Tuist.PubSub.broadcast(%{status: new_status}, topic(account_id), :runner_jobs_status_changed)
    :ok
  end

  defp broadcast_status_change(_, _), do: :ok
end
