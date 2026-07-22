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
  """

  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Runners.JobCompletion
  alias Tuist.Runners.Telemetry
  alias Tuist.Runners.WorkflowJob

  @terminal_statuses ~w(completed cancelled)

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

      Repo.insert_all(WorkflowJob, [row], on_conflict: :nothing)

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
  so redeliveries cannot flip `completed ↔ cancelled`.

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

    {count, _} =
      Repo.insert_all(WorkflowJob, [row],
        on_conflict: on_conflict,
        conflict_target: [:workflow_job_id]
      )

    case count do
      1 -> emit_transition_telemetry(status, "applied")
      0 -> emit_transition_telemetry(status, "miss")
    end

    :ok
  end

  @doc """
  Records the runner→job binding learned from the
  `workflow_job.in_progress` webhook: stamps `runner_name` on the
  executed job's own row, and `executed_workflow_job_id` on the
  row(s) whose claim minted that runner (matched by `runner_name`,
  mirroring `Tuist.Runners.Claims.record_execution/3`). Not a status
  transition. Scoped to the webhook's account, and idempotent under
  redelivery.
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

  # ----- internal -----

  defp transition(workflow_job_id, expected_statuses, new_status, set_fields) do
    now = DateTime.utc_now()
    set_fields = Keyword.merge(set_fields, status: new_status, updated_at: DateTime.truncate(now, :second))

    {count, _} =
      Repo.update_all(
        from(j in WorkflowJob,
          where: j.workflow_job_id == ^workflow_job_id and j.status in ^expected_statuses
        ),
        set: set_fields
      )

    case count do
      1 ->
        emit_transition_telemetry(new_status, "applied")
        :ok

      0 ->
        emit_transition_telemetry(new_status, "miss")
        :noop
    end
  end

  defp emit_transition_telemetry(to_status, outcome) do
    :telemetry.execute(
      Telemetry.event_name_workflow_job_transition(),
      %{count: 1},
      %{to: to_status, outcome: outcome}
    )
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

  defp completion_recorded?(workflow_job_id) do
    Repo.exists?(from(completion in JobCompletion, where: completion.workflow_job_id == ^workflow_job_id))
  end
end
