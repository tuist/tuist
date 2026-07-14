defmodule Tuist.Tests.Workers.BroadcastTestCreatedWorker do
  @moduledoc """
  Broadcasts `:test_created` for a finished test run from inside the web cluster.

  Most runs finish parsing on the xcresult-processor, an isolated,
  non-clustered BEAM node whose in-process `Phoenix.PubSub` (PG2 adapter)
  broadcast never reaches the web tier. `ProcessXcresultWorker` enqueues this
  job on the `:default` queue, which only web pods consume (the processor
  fleets each run a single dedicated queue), so the broadcast always fires on a
  clustered web node and reaches every subscribed LiveView.

  Runs submitted inline on a web node already broadcast in process from
  `Tuist.Tests.create_test/1`; this job is the processor's equivalent.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Tuist.Projects
  alias Tuist.Tests

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"test_run_id" => test_run_id, "project_id" => project_id}}) do
    with {:ok, test} <- Tests.get_test(test_run_id),
         project when not is_nil(project) <- Projects.get_project_by_id(project_id) do
      Tuist.PubSub.broadcast(
        test,
        "#{project.account.name}/#{project.name}",
        :test_created
      )
    end

    :ok
  end
end
