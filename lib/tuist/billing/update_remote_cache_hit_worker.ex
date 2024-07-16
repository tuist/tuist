defmodule Tuist.Billing.UpdateRemoteCacheHitWorker do
  @moduledoc """
  A worker that updates the remote cache hits count for all the paid accounts.
  """
  use Oban.Worker
  alias Tuist.Accounts
  alias Tuist.Repo

  @impl Oban.Worker
  def perform(_job) do
    Repo.transaction(fn ->
      Accounts.get_customer_ids_with_remote_cache_hits_stream()
      |> Stream.each(&Tuist.Billing.update_remote_cache_hit_meter/1)
      |> Stream.run()
    end)

    :ok
  end
end
