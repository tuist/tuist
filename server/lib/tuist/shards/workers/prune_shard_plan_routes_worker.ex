defmodule Tuist.Shards.Workers.PruneShardPlanRoutesWorker do
  @moduledoc false

  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Shards.ShardPlanRoute

  @impl Oban.Worker
  def perform(_job) do
    cutoff = DateTime.add(DateTime.utc_now(), -1, :day)
    old = from route in ShardPlanRoute, where: route.inserted_at < ^cutoff, select: route.plan_id, limit: 1_000
    {deleted, _} = Repo.delete_all(from route in ShardPlanRoute, where: route.plan_id in subquery(old))
    if deleted == 1_000, do: {:snooze, 1}, else: :ok
  end
end
