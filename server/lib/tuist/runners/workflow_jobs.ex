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
  a `:noop`, surfaced via telemetry rather than an error — during the
  dark-write rollout the ClickHouse paths stay authoritative and a
  miss must never fail the caller.

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

  When the `:runner_job_transition_outbox` flag is enabled, each
  applied transition also inserts a
  `Tuist.Runners.WorkflowJobTransitionEvent` row in the same
  transaction, carrying the ClickHouse `runner_jobs` insert shape for
  the batch flusher to replay.
  """

  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Runners.JobCompletion
  alias Tuist.Runners.Telemetry
  alias Tuist.Runners.WorkflowJob
  alias Tuist.Runners.WorkflowJobTransitionEvent

  @terminal_statuses ~w(completed cancelled)
  @outbox_flag :runner_job_transition_outbox

  def outbox_flag, do: @outbox_flag

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
    transition(workflow_job_id, ["claimed", "running"], "queued",
      conclusion: nil,
      pod_name: nil,
      runner_name: nil,
      claimed_at: nil,
      started_at: nil,
      completed_at: nil,
      executed_workflow_job_id: nil
    )
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
    status = if conclusion == "cancelled", do: "cancelled", else: "completed"

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
          {1, [applied]} ->
            emit_transition_event(applied, now)
            emit_transition_telemetry(status, "applied")

          {0, _} ->
            emit_transition_telemetry(status, "miss")
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
        select: %{
          workflow_job_id: j.workflow_job_id,
          account_id: j.account_id,
          repository: j.repository,
          claimed_at: j.claimed_at,
          started_at: j.started_at,
          pod_name: j.pod_name
        }
      )
    )
  end

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

  defp transition(workflow_job_id, expected_statuses, new_status, set_fields) do
    now = DateTime.utc_now()
    set_fields = Keyword.merge(set_fields, status: new_status, updated_at: DateTime.truncate(now, :second))

    {:ok, outcome} =
      Repo.transaction(fn ->
        {count, rows} =
          Repo.update_all(
            from(j in WorkflowJob,
              where: j.workflow_job_id == ^workflow_job_id and j.status in ^expected_statuses,
              select: j
            ),
            set: set_fields
          )

        case {count, rows} do
          {1, [row]} ->
            emit_transition_event(row, now)
            emit_transition_telemetry(new_status, "applied")
            :ok

          {0, _} ->
            emit_transition_telemetry(new_status, "miss")
            :noop
        end
      end)

    outcome
  end

  defp emit_transition_telemetry(to_status, outcome) do
    :telemetry.execute(
      Telemetry.event_name_workflow_job_transition(),
      %{count: 1},
      %{to: to_status, outcome: outcome}
    )
  end

  defp emit_transition_event(%WorkflowJob{} = row, %DateTime{} = transition_at) do
    if FunWithFlags.enabled?(@outbox_flag) do
      Repo.insert_all(WorkflowJobTransitionEvent, [
        %{
          workflow_job_id: row.workflow_job_id,
          account_id: row.account_id,
          payload: ch_row(row, transition_at),
          inserted_at: DateTime.truncate(transition_at, :second)
        }
      ])
    end

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
