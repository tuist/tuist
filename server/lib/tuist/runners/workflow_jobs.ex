defmodule Tuist.Runners.WorkflowJobs do
  @moduledoc """
  Postgres lifecycle store for workflow_jobs — one `runner_workflow_jobs`
  row per `workflow_job_id`, mutated in place through guarded
  compare-and-set transitions.

      queued → claimed → running → completed | cancelled
                  ↑          ↓
                  └── claim release / recovery

  Every transition is an `UPDATE … WHERE status = <expected>` (or an
  upsert whose `ON CONFLICT DO UPDATE` carries the guard), so webhook
  redeliveries and claim races cannot regress a row: a late `queued`
  cannot resurrect a terminal job, a stale `claimed → running` cannot
  overwrite a re-queued one. A transition whose guard doesn't match is
  a `:noop`, not an error — a miss means another path already won (a
  completion raced a claim, a release raced a completion) and the row
  is already where it should be.

  Callers and their transitions:

    * `Tuist.Runners.Jobs.enqueue/1` (webhook `queued`/`waiting`, under
      the per-job ordering lock) → `upsert_queued/1`
    * `Tuist.Runners.Claims.attempt/5` (same transaction as the claim
      insert) → `transition_claimed/3`
    * `Tuist.Runners.Claims.mark_running/2` → `transition_running/2`
    * `Tuist.Runners.Claims.release/2` and `release_pod_missing/2`
      (same transaction as the claim delete) → `requeue/1`
    * `Tuist.Runners.Jobs` completion choke point (webhook `completed`
      plus the recovery workers' force-completes) → `record_completed/3`

  Each applied transition also inserts a
  `Tuist.Runners.WorkflowJobTransitionEvent` row in the same
  transaction, carrying the ClickHouse `runner_jobs` insert shape for
  the batch flusher to replay.
  """

  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Runners.Claim
  alias Tuist.Runners.JobCompletion
  alias Tuist.Runners.WorkflowJob
  alias Tuist.Runners.WorkflowJobTransitionEvent

  @terminal_statuses ~w(completed cancelled)
  @live_statuses ~w(queued claimed running)

  @doc """
  Inserts a `queued` row for the workflow_job when none exists.
  `ON CONFLICT DO NOTHING` on the primary key plus the
  `runner_job_completions` guard make redeliveries safe: an existing
  row — whatever its status — is left alone, and a job whose
  completion is already recorded is never resurrected (mirroring
  `Tuist.Runners.Jobs.enqueue_if_missing/1`).
  """
  def upsert_queued(attrs) when is_map(attrs) do
    workflow_job_id = Map.fetch!(attrs, :workflow_job_id)

    if completion_recorded?(workflow_job_id) do
      :ok
    else
      now = DateTime.utc_now()

      row =
        attrs
        |> base_row()
        |> Map.merge(%{
          status: "queued",
          enqueued_at: Map.get(attrs, :enqueued_at) || now,
          inserted_at: DateTime.truncate(now, :second),
          updated_at: DateTime.truncate(now, :second)
        })

      {:ok, _} =
        Repo.transaction(fn ->
          {count, rows} = Repo.insert_all(WorkflowJob, [row], on_conflict: :nothing, returning: true)

          if count == 1, do: emit_transition_event(hd(rows), now)
        end)

      :ok
    end
  end

  @doc """
  CAS `queued → claimed`. Runs inside `Tuist.Runners.Claims.attempt/5`'s
  transaction so claim insert and lifecycle transition commit or roll
  back together. Returns `:ok` when applied, `:noop` when the row is
  missing or not `queued` (a completion raced the claim, or the row
  predates this table).
  """
  def transition_claimed(workflow_job_id, pod_name, %DateTime{} = claimed_at)
      when is_integer(workflow_job_id) and is_binary(pod_name) do
    transition(workflow_job_id, ["queued"], "claimed", pod_name: pod_name, claimed_at: claimed_at)
  end

  @doc """
  CAS `claimed → running`, stamping the mint-chosen `runner_name`.
  """
  def transition_running(workflow_job_id, runner_name) when is_integer(workflow_job_id) and is_binary(runner_name) do
    transition(workflow_job_id, ["claimed"], "running", runner_name: runner_name, started_at: DateTime.utc_now())
  end

  @doc """
  CAS `claimed | running → queued` — the claim-release transition.
  Clears the claim/runner binding so the row is a clean dispatch
  candidate again. Terminal rows never match the guard, so a release
  racing a completion leaves the completed state alone.
  """
  def requeue(workflow_job_id) when is_integer(workflow_job_id) do
    transition(workflow_job_id, ["claimed", "running"], "queued", requeue_fields())
  end

  @doc """
  Like `requeue/1`, but guarded on the `claimed_at` handle as well as
  the status — the lifecycle-row half of `Tuist.Runners.Claims.release/2`,
  for callers whose claim is already gone.

  `Claims.release_by_pod_name/1` deletes a stopped Pod's claim without
  re-queueing the row, because whether the job should run again is
  GitHub's call (it may be executing on a sibling runner).
  `OrphanedRunnersWorker` makes that call and lands here to finish the
  release: the row still carries the stopped Pod's `claimed_at` only
  if nothing else has touched it since, so a job that was re-claimed
  (newer handle) or completed (terminal status) misses the guard and
  is left alone. Returns `:ok` when applied, `:noop` otherwise.
  """
  def requeue_by_handle(workflow_job_id, %DateTime{} = claimed_at) when is_integer(workflow_job_id) do
    transition(workflow_job_id, ["claimed", "running"], "queued", requeue_fields(), claimed_at: claimed_at)
  end

  defp requeue_fields do
    [
      conclusion: nil,
      pod_name: nil,
      runner_name: nil,
      claimed_at: nil,
      started_at: nil,
      completed_at: nil,
      executed_workflow_job_id: nil
    ]
  end

  @doc """
  Terminal upsert for the completion choke point. Existing rows CAS
  from any non-terminal status; a missing row (completed delivered
  before queued, or the job predates this table) is inserted terminal
  so late `queued` redeliveries hit the `ON CONFLICT DO NOTHING`
  guard in `upsert_queued/1`. Already-terminal rows are left alone,
  so redeliveries cannot flip `completed ↔ cancelled` or re-emit
  outbox events.

  A `"cancelled"` conclusion maps to status `"cancelled"`; everything
  else lands as `"completed"` with the conclusion recorded alongside.
  """
  def record_completed(attrs, conclusion, %DateTime{} = completed_at) when is_map(attrs) and is_binary(conclusion) do
    now = DateTime.utc_now()
    truncated_now = DateTime.truncate(now, :second)
    status = terminal_status(conclusion)

    row =
      attrs
      |> base_row()
      |> Map.merge(%{
        status: status,
        conclusion: conclusion,
        enqueued_at: Map.get(attrs, :enqueued_at) || completed_at,
        claimed_at: Map.get(attrs, :claimed_at),
        started_at: Map.get(attrs, :started_at),
        pod_name: blank_to_nil(Map.get(attrs, :pod_name)),
        runner_name: blank_to_nil(Map.get(attrs, :runner_name)),
        completed_at: completed_at,
        inserted_at: truncated_now,
        updated_at: truncated_now
      })

    on_conflict =
      from(j in WorkflowJob,
        where: j.status not in ^@terminal_statuses,
        update: [
          set: [status: ^status, conclusion: ^conclusion, completed_at: ^completed_at, updated_at: ^truncated_now]
        ]
      )

    {:ok, _} =
      Repo.transaction(fn ->
        {count, rows} =
          Repo.insert_all(WorkflowJob, [row],
            on_conflict: on_conflict,
            conflict_target: [:workflow_job_id],
            returning: true
          )

        case {count, rows} do
          {1, [applied]} -> emit_transition_event(applied, now)
          {0, _} -> :ok
        end
      end)

    :ok
  end

  @doc """
  Records the runner→job binding learned from the
  `workflow_job.in_progress` webhook: stamps `runner_name` on the
  executed job's own row, and `executed_workflow_job_id` on the
  row(s) whose claim minted that runner (matched by `runner_name`,
  mirroring `Tuist.Runners.Claims.record_execution/3`). Not a status
  transition — no outbox event. Scoped to the webhook's account, and
  idempotent under redelivery.
  """
  def record_execution(runner_name, executed_workflow_job_id, account_id)
      when is_binary(runner_name) and runner_name != "" and is_integer(executed_workflow_job_id) and
             is_integer(account_id) do
    Repo.update_all(
      from(j in WorkflowJob, where: j.workflow_job_id == ^executed_workflow_job_id and j.account_id == ^account_id),
      set: [runner_name: runner_name]
    )

    Repo.update_all(
      from(j in WorkflowJob, where: j.runner_name == ^runner_name and j.account_id == ^account_id),
      set: [executed_workflow_job_id: executed_workflow_job_id]
    )

    :ok
  end

  def record_execution(_runner_name, _executed_workflow_job_id, _account_id), do: :ok

  @doc """
  Postgres twin of `Tuist.Runners.Jobs.pick_queued_top_k/5`, returning
  the same candidate map shape in the same deterministic
  `(enqueued_at ASC, workflow_job_id ASC)` order. `enqueued_floor`
  mirrors the ClickHouse read's lookback bound so a flag flip cannot
  resurface jobs the CH path had already aged out of view.
  """
  def pick_queued_top_k(
        fleet_name,
        ineligible_account_ids,
        excluded_repositories,
        excluded_workflow_job_ids,
        k,
        %DateTime{} = enqueued_floor
      )
      when is_binary(fleet_name) and is_integer(k) and k > 0 do
    from(j in WorkflowJob,
      where: j.fleet_name == ^fleet_name and j.status == "queued" and j.enqueued_at > ^enqueued_floor,
      order_by: [asc: j.enqueued_at, asc: j.workflow_job_id],
      limit: ^k,
      select: %{
        workflow_job_id: j.workflow_job_id,
        account_id: j.account_id,
        fleet_name: j.fleet_name,
        platform: j.platform,
        vcpus: j.vcpus,
        memory_gb: j.memory_gb,
        repository: j.repository,
        workflow_run_id: j.workflow_run_id,
        workflow_name: j.workflow_name,
        run_attempt: j.run_attempt,
        job_name: j.job_name,
        head_branch: j.head_branch,
        head_sha: j.head_sha,
        enqueued_at: j.enqueued_at,
        requested_dispatch_label: j.requested_dispatch_label
      }
    )
    |> exclude_accounts(ineligible_account_ids)
    |> exclude_repositories(excluded_repositories)
    |> exclude_workflow_jobs(excluded_workflow_job_ids)
    |> Repo.all()
    |> case do
      [] -> {:error, :empty}
      candidates -> {:ok, candidates}
    end
  end

  @doc """
  Postgres twin of `Tuist.Runners.Jobs.queued_count_by_fleet/1`.
  """
  def queued_count_by_fleet(fleet_name, %DateTime{} = enqueued_floor) when is_binary(fleet_name) do
    Repo.aggregate(
      from(j in WorkflowJob,
        where: j.fleet_name == ^fleet_name and j.status == "queued" and j.enqueued_at > ^enqueued_floor
      ),
      :count
    )
  end

  @doc """
  Postgres twin of `Tuist.Runners.Jobs.queued_count_by_fleet_and_account/1`.
  """
  def queued_count_by_fleet_and_account(fleet_name, %DateTime{} = enqueued_floor) when is_binary(fleet_name) do
    from(j in WorkflowJob,
      where: j.fleet_name == ^fleet_name and j.status == "queued" and j.enqueued_at > ^enqueued_floor,
      group_by: j.account_id,
      select: {j.account_id, count()}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Postgres twin of `Tuist.Runners.Jobs.list_orphaned_running/1`,
  feeding `OrphanedRunnersWorker`'s candidate scan: `running` rows
  whose `started_at` is older than `threshold`, in the same map shape
  (`claimed_at` is the claim-release handle — written from the same
  `DateTime` as the claim row's, in the same transaction, so the
  handle matches regardless of which store served the scan).
  """
  def list_orphaned_running(%DateTime{} = threshold) do
    Repo.all(
      from(j in WorkflowJob,
        where: j.status == "running" and j.started_at < ^threshold,
        select: map(j, ^orphan_fields())
      )
    )
  end

  @doc """
  Postgres twin of `Tuist.Runners.Jobs.get_orphaned_running/1`: the
  same recovery shape for one workflow_job, or `nil` unless the row's
  current status is `running`. Feeds `OrphanedRunnersWorker`'s
  targeted mode, where the caller already holds evidence the Pod is
  gone and needs no age gate.
  """
  def get_orphaned_running(workflow_job_id) when is_integer(workflow_job_id) do
    Repo.one(
      from(j in WorkflowJob,
        where: j.workflow_job_id == ^workflow_job_id and j.status == "running",
        select: map(j, ^orphan_fields())
      )
    )
  end

  @orphan_fields [:workflow_job_id, :account_id, :repository, :claimed_at, :started_at, :pod_name, :fleet_name]

  defp orphan_fields, do: @orphan_fields

  @doc """
  Postgres twin of `Tuist.Runners.Jobs.list_stale_queued/2`, feeding
  `StaleQueuedJobsWorker`'s candidate scan: `queued` rows whose
  `enqueued_at` falls in `(enqueued_after, enqueued_before)`, in the
  same map shape.
  """
  def list_stale_queued(%DateTime{} = enqueued_after, %DateTime{} = enqueued_before) do
    Repo.all(
      from(j in WorkflowJob,
        where: j.status == "queued" and j.enqueued_at > ^enqueued_after and j.enqueued_at < ^enqueued_before,
        select: %{
          workflow_job_id: j.workflow_job_id,
          account_id: j.account_id,
          repository: j.repository,
          enqueued_at: j.enqueued_at
        }
      )
    )
  end

  @doc """
  Adopts a lifecycle row for a job that exists only in ClickHouse —
  enqueued by code that predates this table — in its current
  ClickHouse status. Returns the number of rows inserted (`0` or `1`).

  Must run inside `Tuist.Runners.Jobs.with_workflow_job_ordering_lock/2`:
  every completion writer (this release and the one before it) takes
  that lock, so the completion check and the insert cannot straddle a
  completion landing in between. `ON CONFLICT DO NOTHING` covers a
  race with a live transition that created the row first. Adopted rows
  emit no outbox event — ClickHouse is the source here, so there is
  nothing to replicate back.

  Transitional, used only by
  `Tuist.Runners.Workers.ReconcileWorkflowJobsWorker`; deleted with it.
  """
  def adopt(ch_row) when is_map(ch_row) do
    if completion_recorded?(ch_row.workflow_job_id) do
      0
    else
      now = DateTime.truncate(DateTime.utc_now(), :second)

      row =
        ch_row
        |> base_row()
        |> Map.merge(%{
          status: adopt_status(ch_row),
          enqueued_at: ch_row.enqueued_at,
          claimed_at: Map.get(ch_row, :claimed_at),
          started_at: Map.get(ch_row, :started_at),
          pod_name: blank_to_nil(Map.get(ch_row, :pod_name)),
          runner_name: blank_to_nil(Map.get(ch_row, :runner_name)),
          inserted_at: now,
          updated_at: now
        })

      {count, _} = Repo.insert_all(WorkflowJob, [row], on_conflict: :nothing)
      count
    end
  end

  defp adopt_status(%{status: "completed", conclusion: "cancelled"}), do: "cancelled"
  defp adopt_status(%{status: status}), do: status

  @doc """
  Which of `workflow_job_ids` already have a completion recorded.
  Batched prefilter for adoption so the per-row locked check only runs
  for candidates that might still be live.
  """
  def completed_ids(workflow_job_ids) when is_list(workflow_job_ids) do
    Repo.all(
      from(c in JobCompletion,
        where: c.workflow_job_id in ^workflow_job_ids,
        select: c.workflow_job_id
      )
    )
  end

  @doc """
  Closes lifecycle rows still non-terminal for a job whose completion
  is recorded. Returns the number of rows transitioned.

  A `runner_job_completions` row is proof the job is over, written by
  every completion path — including the previous release's, which
  never touches this table. While old and new pods overlap (a roll,
  or a rollback and roll-forward), a job the old code completed keeps
  its Postgres row wherever it was — `queued` churns dispatch, and
  `claimed`/`running` looks live to the recovery scans — until this
  closes it with the completion's own conclusion.
  """
  def close_completed do
    stale =
      Repo.all(
        from(j in WorkflowJob,
          join: c in JobCompletion,
          on: c.workflow_job_id == j.workflow_job_id,
          where: j.status in ^@live_statuses,
          select: {j.workflow_job_id, c.conclusion, c.completed_at}
        )
      )

    Enum.count(stale, fn {workflow_job_id, conclusion, completed_at} ->
      completed_at = completed_at || DateTime.utc_now()

      transition(workflow_job_id, @live_statuses, terminal_status(conclusion),
        conclusion: conclusion,
        completed_at: completed_at
      ) == :ok
    end)
  end

  @doc """
  Re-queues `claimed` lifecycle rows that no live claim backs. Returns
  the number of rows transitioned.

  Under this release a claim and its `claimed` row are created and
  released in one transaction, so the state cannot arise on its own.
  It appears when the previous release's code releases a claim this
  release made — its stale-claim sweep and pod-stopped path delete
  the claim without touching this table — leaving the job invisible
  to dispatch (not `queued`) and to every recovery scan (no claim to
  list, not `running`). A `claimed` row is by construction pre-mint,
  so nothing can be running for it and the requeue is safe; the
  handle guard leaves a row that was re-claimed in the meantime alone.
  """
  def requeue_unbacked_claimed do
    unbacked =
      Repo.all(
        from(j in WorkflowJob,
          left_join: c in Claim,
          on: c.workflow_job_id == j.workflow_job_id,
          where: j.status == "claimed" and is_nil(c.workflow_job_id),
          select: {j.workflow_job_id, j.claimed_at}
        )
      )

    Enum.count(unbacked, fn
      {workflow_job_id, %DateTime{} = claimed_at} -> requeue_by_handle(workflow_job_id, claimed_at) == :ok
      {workflow_job_id, nil} -> requeue(workflow_job_id) == :ok
    end)
  end

  @doc """
  Moves `queued` lifecycle rows that a live claim already backs into
  the claim's state. Returns the number of rows transitioned.

  The previous release's `Claims.attempt/5` and `mark_running/2` write
  the claim only, so a job this release enqueued and the old code
  claimed reads `queued` here while a Pod holds it. Dispatch would
  keep offering it (each attempt losing the claim race by primary
  key), and the recovery scans would miss it — this brings the row to
  where the claim says it is.
  """
  def sync_claimed_from_claims do
    backed =
      Repo.all(
        from(j in WorkflowJob,
          join: c in Claim,
          on: c.workflow_job_id == j.workflow_job_id,
          where: j.status == "queued",
          select: {j.workflow_job_id, c.pod_name, c.claimed_at, c.lifecycle_state, c.runner_name}
        )
      )

    Enum.count(backed, fn {workflow_job_id, pod_name, claimed_at, lifecycle_state, runner_name} ->
      case transition_claimed(workflow_job_id, pod_name, claimed_at) do
        :ok ->
          if lifecycle_state == "running", do: transition_running(workflow_job_id, runner_name || "")
          true

        :noop ->
          false
      end
    end)
  end

  @doc """
  The terminal status a conclusion maps to: `"cancelled"` for a
  cancelled conclusion, `"completed"` for everything else.
  """
  def terminal_status("cancelled"), do: "cancelled"
  def terminal_status(_conclusion), do: "completed"

  @doc """
  Rows whose `updated_at` falls in `(updated_after, updated_before)`,
  newest first, capped at `limit`. Feeds the drift comparator: the
  upper bound keeps rows mid-transition (Postgres committed, the
  paired ClickHouse INSERT still in flight) out of the diff.
  """
  def list_recently_updated(%DateTime{} = updated_after, %DateTime{} = updated_before, limit)
      when is_integer(limit) and limit > 0 do
    Repo.all(
      from(j in WorkflowJob,
        where: j.updated_at > ^updated_after and j.updated_at < ^updated_before,
        order_by: [desc: j.updated_at],
        limit: ^limit,
        select: %{workflow_job_id: j.workflow_job_id, status: j.status, enqueued_at: j.enqueued_at}
      )
    )
  end

  @doc """
  Decodes a transition event's JSONB payload back into the ClickHouse
  `runner_jobs` insert row: string keys to atoms, ISO-8601 datetimes
  to `DateTime` promoted to microsecond precision for
  `DateTime64(6)` binding.
  """
  def decode_transition_payload(payload) when is_map(payload) do
    %{
      workflow_job_id: payload["workflow_job_id"],
      account_id: payload["account_id"],
      fleet_name: payload["fleet_name"],
      repository: payload["repository"],
      platform: payload["platform"],
      vcpus: payload["vcpus"],
      memory_gb: payload["memory_gb"],
      workflow_run_id: payload["workflow_run_id"],
      workflow_name: payload["workflow_name"],
      run_attempt: payload["run_attempt"],
      job_name: payload["job_name"],
      head_branch: payload["head_branch"],
      head_sha: payload["head_sha"],
      status: payload["status"],
      conclusion: payload["conclusion"],
      enqueued_at: parse_datetime(payload["enqueued_at"]),
      claimed_at: parse_datetime(payload["claimed_at"]),
      started_at: parse_datetime(payload["started_at"]),
      completed_at: parse_datetime(payload["completed_at"]),
      pod_name: payload["pod_name"],
      runner_name: payload["runner_name"],
      requested_dispatch_label: payload["requested_dispatch_label"],
      updated_at: parse_datetime(payload["updated_at"])
    }
  end

  # ----- internal -----

  defp transition(workflow_job_id, expected_statuses, new_status, set_fields, guards \\ []) do
    now = DateTime.utc_now()
    set_fields = Keyword.merge(set_fields, status: new_status, updated_at: DateTime.truncate(now, :second))

    {:ok, outcome} =
      Repo.transaction(fn ->
        {count, rows} =
          from(j in WorkflowJob,
            where: j.workflow_job_id == ^workflow_job_id and j.status in ^expected_statuses,
            select: j
          )
          |> apply_guards(guards)
          |> Repo.update_all(set: set_fields)

        case {count, rows} do
          {1, [row]} ->
            emit_transition_event(row, now)
            :ok

          {0, _} ->
            :noop
        end
      end)

    outcome
  end

  defp apply_guards(query, []), do: query

  defp apply_guards(query, claimed_at: %DateTime{} = claimed_at) do
    where(query, [j], j.claimed_at == ^claimed_at)
  end

  defp emit_transition_event(%WorkflowJob{} = row, %DateTime{} = transition_at) do
    Repo.insert_all(WorkflowJobTransitionEvent, [
      %{
        workflow_job_id: row.workflow_job_id,
        account_id: row.account_id,
        payload: ch_row(row, transition_at),
        inserted_at: DateTime.truncate(transition_at, :second)
      }
    ])

    :ok
  end

  # The ClickHouse `runner_jobs` insert shape for this row's current
  # state. `updated_at` is the transition timestamp at microsecond
  # precision (the RMT version column is DateTime64(6); the row's own
  # `updated_at` is second-truncated), so replayed rows sort correctly
  # against the direct CH writes that remain on during rollout. Status
  # `cancelled` maps back to CH's `completed` + conclusion convention.
  defp ch_row(%WorkflowJob{} = row, %DateTime{} = transition_at) do
    %{
      workflow_job_id: row.workflow_job_id,
      account_id: row.account_id,
      fleet_name: row.fleet_name,
      repository: row.repository,
      platform: row.platform,
      vcpus: row.vcpus,
      memory_gb: row.memory_gb,
      workflow_run_id: row.workflow_run_id,
      workflow_name: row.workflow_name,
      run_attempt: row.run_attempt,
      job_name: row.job_name,
      head_branch: row.head_branch,
      head_sha: row.head_sha,
      status: ch_status(row.status),
      conclusion: row.conclusion || "",
      enqueued_at: row.enqueued_at,
      claimed_at: row.claimed_at,
      started_at: row.started_at,
      completed_at: row.completed_at,
      pod_name: row.pod_name || "",
      runner_name: row.runner_name || "",
      requested_dispatch_label: row.requested_dispatch_label,
      updated_at: transition_at
    }
  end

  defp ch_status("cancelled"), do: "completed"
  defp ch_status(status), do: status

  defp parse_datetime(nil), do: nil
  defp parse_datetime(%DateTime{} = datetime), do: datetime

  defp parse_datetime(value) when is_binary(value) do
    {:ok, %DateTime{microsecond: {us, _}} = datetime, _offset} = DateTime.from_iso8601(value)
    %{datetime | microsecond: {us, 6}}
  end

  @candidate_defaults [
    platform: "",
    vcpus: 0,
    memory_gb: 0,
    repository: "",
    workflow_run_id: 0,
    workflow_name: "",
    run_attempt: 1,
    job_name: "",
    head_branch: "",
    head_sha: "",
    requested_dispatch_label: ""
  ]

  defp base_row(attrs) do
    base = %{
      workflow_job_id: Map.fetch!(attrs, :workflow_job_id),
      account_id: Map.fetch!(attrs, :account_id),
      fleet_name: Map.fetch!(attrs, :fleet_name)
    }

    Enum.reduce(@candidate_defaults, base, fn {key, default}, acc ->
      Map.put(acc, key, Map.get(attrs, key) || default)
    end)
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp exclude_accounts(query, []), do: query

  defp exclude_accounts(query, account_ids) when is_list(account_ids) do
    where(query, [j], j.account_id not in ^account_ids)
  end

  defp exclude_repositories(query, []), do: query

  defp exclude_repositories(query, repositories) when is_list(repositories) do
    where(query, [j], j.repository not in ^repositories)
  end

  defp exclude_workflow_jobs(query, []), do: query

  defp exclude_workflow_jobs(query, workflow_job_ids) when is_list(workflow_job_ids) do
    where(query, [j], j.workflow_job_id not in ^workflow_job_ids)
  end

  defp completion_recorded?(workflow_job_id) do
    Repo.exists?(from(completion in JobCompletion, where: completion.workflow_job_id == ^workflow_job_id))
  end
end
