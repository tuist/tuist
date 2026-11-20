defmodule LuftServer.Notifications.PruneWorker do
  @moduledoc "Bounded retirement of expired activities, old tombstones and stale start tokens."
  use Oban.Worker, queue: :push, max_attempts: 3, unique: [period: 60, states: :incomplete]

  alias LuftServer.Notifications.LiveActivities

  @impl true
  def perform(_) do
    %{retired: retired, deleted: deleted, starters: starters} = LiveActivities.prune()

    if LiveActivities.prune_batch_size() in [retired, deleted, starters],
      do: {:snooze, 1},
      else: :ok
  end
end
