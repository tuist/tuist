defmodule Tuist.Push.Workers.PruneWorker do
  @moduledoc """
  Prunes push registrations in bounded batches, snoozing while there is more.
  """

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 60, states: :incomplete]

  alias Tuist.Push

  @impl Oban.Worker
  def perform(_job) do
    %{retired: retired, deleted: deleted} = Push.prune()
    if Push.prune_batch_size() in [retired, deleted], do: {:snooze, 1}, else: :ok
  end
end
