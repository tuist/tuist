defmodule Tuist.Push.Workers.PruneWorker do
  @moduledoc false

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Tuist.Push

  @impl Oban.Worker
  def perform(_job) do
    {:ok, _counts} = Push.prune()
    :ok
  end
end
