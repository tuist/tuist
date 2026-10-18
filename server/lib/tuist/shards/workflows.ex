defmodule Tuist.Shards.Workflows do
  @moduledoc """
  PostgreSQL-owned shard workflows. Transactions serialize the control plane;
  ClickHouse is an asynchronous, duplicate-tolerant projection, never a merge base.
  """
  import Ecto.Query

  alias Ecto.Changeset
  alias Tuist.Repo
  alias Tuist.Shards.ShardPlan
  alias Tuist.Shards.ShardPlanModule
  alias Tuist.Shards.ShardPlanTestSuite
  alias Tuist.Shards.ShardRun
  alias Tuist.Shards.Workers.ProjectWorkflowWorker
  alias Tuist.Shards.Workflow
  alias Tuist.Shards.WorkflowShard
  alias Tuist.Tests.Test

  @terminal_statuses ~w(success failure skipped failed_processing)

  def create(%ShardPlan{} = plan, modules, suites) do
    {:ok, workflow} =
      Repo.transaction(fn ->
        attrs =
          Map.take(plan, [:id, :project_id, :reference, :shard_count, :granularity, :build_run_id, :gradle_build_id])

        now = database_now()

        workflow =
          struct!(Workflow, Map.merge(attrs, %{test_run_id: UUIDv7.generate(), inserted_at: now, updated_at: now}))

        workflow = Repo.insert!(workflow)

        rows =
          Enum.map(0..(plan.shard_count - 1), fn index ->
            %{
              workflow_id: plan.id,
              shard_index: index,
              assignment: %{
                modules: Enum.filter(modules, &(&1.shard_index == index)),
                test_suites: Enum.filter(suites, &(&1.shard_index == index))
              }
            }
          end)

        Repo.insert_all(WorkflowShard, rows)
        enqueue_projection(workflow)
        Repo.preload(workflow, :shards)
      end)

    to_plan(workflow)
  end

  def get(id, project_id \\ nil) do
    query = where(Workflow, id: ^id)
    query = if project_id, do: where(query, project_id: ^project_id), else: query
    query |> Repo.one() |> preload_shards()
  end

  def owns_reference?(project_id, reference) do
    Repo.exists?(from(w in Workflow, where: w.project_id == ^project_id and w.reference == ^reference))
  end

  def get_by_reference(project_id, reference) do
    Workflow
    |> where(project_id: ^project_id, reference: ^reference)
    |> order_by([w], desc: w.inserted_at, desc: w.id)
    |> limit(1)
    |> Repo.one()
    |> preload_shards()
  end

  def get_test(id) do
    case Repo.one(from(w in Workflow, where: w.test_run_id == ^id)) do
      nil -> nil
      workflow -> snapshot(workflow)
    end
  end

  def owned_ids(ids) do
    Workflow
    |> where([w], w.id in ^ids)
    |> select([w], w.id)
    |> Repo.all()
    |> MapSet.new()
  end

  def plans(ids) do
    Workflow
    |> where([w], w.id in ^ids)
    |> Repo.all()
    |> Repo.preload(:shards)
    |> Map.new(&{&1.id, to_plan(&1)})
  end

  def to_plan(%Workflow{} = workflow) do
    attrs =
      Map.take(workflow, [:id, :project_id, :reference, :shard_count, :granularity, :build_run_id, :gradle_build_id])

    inserted_at = DateTime.to_naive(workflow.inserted_at)

    struct!(
      ShardPlan,
      Map.merge(attrs, %{
        inserted_at: inserted_at,
        authority: :postgres,
        merged_test_run_id: workflow.test_run_id,
        modules: assignment_rows(workflow, "modules", ShardPlanModule),
        test_suites: assignment_rows(workflow, "test_suites", ShardPlanTestSuite),
        shard_runs: shard_rows(workflow, inserted_at)
      })
    )
  end

  def snapshot(%Workflow{snapshot: nil}), do: nil

  def snapshot(%Workflow{snapshot: snapshot}) do
    %Test{}
    |> Changeset.cast(snapshot, Test.__schema__(:fields))
    |> Changeset.apply_changes()
  end

  @doc """
  Records completion only after the caller has staged this report's core facts.
  The callback merges a small snapshot and must not do external work while locked.
  """
  def record_report(plan, index, status, duration, merge, opts \\ []) do
    Repo.transaction(fn ->
      workflow = lock_workflow(plan.id, plan.project_id)
      shard = Repo.get_by!(WorkflowShard, workflow_id: plan.id, shard_index: index)

      # A retried initial upload must not supersede parsed status or metadata.
      if status == "processing" and shard.status in @terminal_statuses do
        snapshot(workflow)
      else
        commit_report(workflow, shard, status, duration, merge, opts)
      end
    end)
  end

  defp commit_report(workflow, shard, status, duration, merge, opts) do
    now = database_now()
    version = max(DateTime.to_unix(now, :microsecond), workflow.version + 1)
    reported_at = DateTime.from_unix!(version, :microsecond)

    shard
    |> Changeset.change(
      status: status,
      duration: duration,
      ran_at: Keyword.get(opts, :ran_at, now),
      reported_at: reported_at
    )
    |> Repo.update!()

    statuses =
      Repo.all(from(s in WorkflowShard, where: s.workflow_id == ^workflow.id and not is_nil(s.status), select: s.status))

    test = merge.(snapshot(workflow), statuses)
    test = %{test | inserted_at: DateTime.to_naive(reported_at)}
    payload = Map.take(test, Test.__schema__(:fields))

    workflow
    |> Changeset.change(snapshot: payload, version: version, updated_at: now)
    |> Repo.update!()
    |> enqueue_projection()

    test
  end

  def mark_projected(%Workflow{} = workflow) do
    Repo.update_all(
      from(w in Workflow, where: w.id == ^workflow.id and w.projected_version < ^workflow.version),
      set: [projected_version: workflow.version]
    )

    :ok
  end

  @doc "Repairs missing, discarded or pruned projection jobs in bounded hourly batches."
  def reconcile_pending(limit \\ 500) when limit in 1..500 do
    pending =
      Repo.all(
        from(w in Workflow,
          where: w.projected_version < w.version,
          order_by: [asc_nulls_first: w.projection_repair_at, asc: w.id],
          limit: ^limit,
          select: %{id: w.id, project_id: w.project_id}
        )
      )

    ids = Enum.map(pending, & &1.id)

    # Rotate attempts, not report activity: poisoned rows must not starve the
    # next batch or reset the deadline used by the stale-report reaper.
    Repo.update_all(from(w in Workflow, where: w.id in ^ids), set: [projection_repair_at: database_now()])
    Enum.each(pending, &enqueue_projection/1)
    :ok
  end

  def expire_stale(cutoff) do
    ids =
      Repo.all(
        from(w in Workflow,
          where: w.updated_at < ^cutoff and fragment("?->>'status' = 'in_progress'", w.snapshot),
          order_by: [asc: w.updated_at, asc: w.id],
          limit: 500,
          select: {w.id, w.project_id}
        )
      )

    Enum.each(ids, fn {id, project_id} ->
      Repo.transaction(fn ->
        workflow = lock_workflow(id, project_id)
        test = snapshot(workflow)

        if test && test.status == "in_progress" && DateTime.before?(workflow.updated_at, cutoff) do
          now = database_now()
          version = max(DateTime.to_unix(now, :microsecond), workflow.version + 1)
          reported_at = DateTime.from_unix!(version, :microsecond)
          test = %{test | status: "failure", inserted_at: DateTime.to_naive(reported_at)}

          Repo.update_all(
            from(s in WorkflowShard,
              where: s.workflow_id == ^id and (is_nil(s.status) or s.status in ["processing", "in_progress"])
            ),
            set: [status: "failure", reported_at: reported_at, ran_at: now]
          )

          workflow
          |> Changeset.change(snapshot: Map.take(test, Test.__schema__(:fields)), version: version, updated_at: now)
          |> Repo.update!()
          |> enqueue_projection()
        end
      end)
    end)
  end

  defp enqueue_projection(workflow) do
    %{workflow_id: workflow.id, project_id: workflow.project_id}
    |> ProjectWorkflowWorker.new()
    |> Oban.insert!()
  end

  defp lock_workflow(id, project_id) do
    Repo.one!(from(w in Workflow, where: w.id == ^id and w.project_id == ^project_id, lock: "FOR UPDATE"))
  end

  defp database_now do
    %{rows: [[now]]} = Repo.query!("SELECT clock_timestamp()")
    now
  end

  defp preload_shards(nil), do: nil
  defp preload_shards(workflow), do: Repo.preload(workflow, :shards)

  defp assignment_rows(workflow, key, schema) do
    fields = schema.__schema__(:fields)

    Enum.flat_map(workflow.shards, fn shard ->
      Enum.map(Map.get(shard.assignment, key, []), fn row ->
        schema
        |> struct()
        |> Changeset.cast(row, fields)
        |> Changeset.apply_changes()
      end)
    end)
  end

  defp shard_rows(workflow, inserted_at) do
    workflow.shards
    |> Enum.reject(&is_nil(&1.status))
    |> Enum.map(fn shard ->
      %ShardRun{
        shard_plan_id: workflow.id,
        project_id: workflow.project_id,
        test_run_id: workflow.test_run_id,
        shard_index: shard.shard_index,
        status: shard.status,
        duration: shard.duration,
        ran_at: if(shard.ran_at, do: DateTime.to_naive(shard.ran_at), else: inserted_at),
        inserted_at: DateTime.to_naive(shard.reported_at)
      }
    end)
  end
end
