defmodule Tuist.Shards.Workers.ProjectWorkflowWorker do
  @moduledoc """
  Projects durable workflow state into ClickHouse. Jobs are inserted in the
  control-plane transaction. Executing jobs do not absorb a later update, so
  an update committed during publication always gets another publication.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 20,
    unique: [keys: [:workflow_id], states: [:available, :scheduled, :retryable], period: :infinity]

  alias Tuist.IngestRepo
  alias Tuist.MCP.Events.Publisher
  alias Tuist.Shards.ShardPlan
  alias Tuist.Shards.ShardRun
  alias Tuist.Shards.Workflows
  alias Tuist.Tests.Test

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"workflow_id" => id, "project_id" => project_id}}) do
    case Workflows.get(id, project_id) do
      nil ->
        :ok

      workflow ->
        :ok = project(workflow)
        Workflows.mark_projected(workflow)
    end
  end

  defp project(workflow) do
    plan = Workflows.to_plan(workflow)
    row = Map.take(plan, ShardPlan.__schema__(:fields))
    IngestRepo.insert_all(ShardPlan, [row], settings: [insert_deduplication_token: "shard-plan:#{plan.id}"])

    # Replay is at least once. Shard-run readers collapse reports by shard
    # and report time; deduplication tokens are an optimization, not authority.
    if plan.shard_runs != [] do
      rows = Enum.map(plan.shard_runs, &Map.take(&1, ShardRun.__schema__(:fields)))
      token = "shard-reports:#{plan.id}:#{workflow.version}"
      IngestRepo.insert_all(ShardRun, rows, settings: [insert_deduplication_token: token])
    end

    case Workflows.snapshot(workflow) do
      nil ->
        :ok

      test ->
        IngestRepo.insert_all(Test, [Map.take(test, Test.__schema__(:fields))])

        if test.status == "failure" do
          Publisher.publish(
            "test_run.failed",
            %{
              "project_id" => test.project_id,
              "test_run_id" => test.id,
              "is_ci" => test.is_ci,
              "git_branch" => test.git_branch || ""
            },
            test.id
          )
        end

        :ok
    end
  end
end
