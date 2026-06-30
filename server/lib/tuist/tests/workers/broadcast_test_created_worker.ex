defmodule Tuist.Tests.Workers.BroadcastTestCreatedWorker do
  @moduledoc """
  Relays the `:test_created` PubSub notification so it runs on a web node.

  `Tuist.Tests.create_test/1` broadcasts `:test_created` to refresh any open
  test dashboards. When it runs on the xcresult-processor, though, that
  broadcast is emitted on an isolated, non-clustered BEAM node whose
  `Phoenix.PubSub` (PG2 adapter) never reaches the web tier — so a run that
  finished processing stays stuck on the "processing" spinner until the page is
  refreshed.

  Enqueuing this job decouples the broadcast from the node that created the run:
  it lands on the `:default` queue, which only web pods consume (the processor
  fleets run a single dedicated queue each), so the broadcast always fires on a
  clustered web node and reaches every subscribed LiveView.
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
