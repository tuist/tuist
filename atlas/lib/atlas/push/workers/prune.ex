defmodule Atlas.Push.Workers.Prune do
  @moduledoc false

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Atlas.Push

  @impl Oban.Worker
  def perform(_job) do
    {:ok, _counts} = Push.prune()
    :ok
  end
end
