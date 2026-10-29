defmodule Tuist.MCP.Events.Workers.PruneJobKeysWorker do
  @moduledoc false

  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query

  alias Tuist.MCP.Events.JobKey
  alias Tuist.Repo

  @impl Oban.Worker
  def perform(_job) do
    cutoff = DateTime.add(DateTime.utc_now(), -31, :day)
    old_keys = from key in JobKey, where: key.inserted_at < ^cutoff, select: key.key, limit: 1_000
    {deleted, _} = Repo.delete_all(from key in JobKey, where: key.key in subquery(old_keys))
    if deleted == 1_000, do: {:snooze, 1}, else: :ok
  end
end
