defmodule Tuist.Push.Workers.PruneWorker do
  @moduledoc """
  Prunes push registrations in bounded batches, snoozing while there is more.
  """

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 60, states: :incomplete]

  alias Tuist.Push
  alias Tuist.Push.LiveActivities

  @impl Oban.Worker
  def perform(_job) do
    %{retired: retired, deleted: deleted} = Push.prune()
    %{retired: activities_retired, deleted: activities_deleted} = LiveActivities.prune()

    if Push.prune_batch_size() in [retired, deleted, activities_retired, activities_deleted],
      do: {:snooze, 1},
      else: :ok
  end
end
