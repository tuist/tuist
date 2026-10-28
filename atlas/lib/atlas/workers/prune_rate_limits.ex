defmodule Atlas.Workers.PruneRateLimits do
  @moduledoc false

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Atlas.RateLimit

  @impl Oban.Worker
  def perform(_job), do: RateLimit.prune_expired()
end
