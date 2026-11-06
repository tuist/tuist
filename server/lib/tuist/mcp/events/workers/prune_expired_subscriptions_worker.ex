defmodule Tuist.MCP.Events.Workers.PruneExpiredSubscriptionsWorker do
  @moduledoc false

  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query

  alias Tuist.MCP.Events.Subscription
  alias Tuist.Repo

  @impl Oban.Worker
  def perform(_job) do
    cutoff = DateTime.add(DateTime.utc_now(), -24 * 60 * 60, :second)

    Repo.delete_all(from subscription in Subscription, where: subscription.refresh_before < ^cutoff)

    :ok
  end
end
