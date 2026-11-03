defmodule Tuist.Shards.Workers.PruneRecentShardPlansWorker do
  @moduledoc false

  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Shards.RecentShardPlan

  @impl Oban.Worker
  def perform(_job) do
    cutoff = DateTime.add(DateTime.utc_now(), -1, :day)
    old = from plan in RecentShardPlan, where: plan.inserted_at < ^cutoff, select: plan.plan_id, limit: 1_000
    {deleted, _} = Repo.delete_all(from plan in RecentShardPlan, where: plan.plan_id in subquery(old))
    if deleted == 1_000, do: {:snooze, 1}, else: :ok
  end
end
