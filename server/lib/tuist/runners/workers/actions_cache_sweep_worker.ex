defmodule Tuist.Runners.Workers.ActionsCacheSweepWorker do
  @moduledoc false
  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 300]

  alias Tuist.Runners.ActionsCache

  @impl Oban.Worker
  def perform(_job) do
    with {:ok, _count} <- ActionsCache.sweep(), do: :ok
  end
end
