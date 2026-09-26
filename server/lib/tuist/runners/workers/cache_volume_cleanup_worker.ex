defmodule Tuist.Runners.Workers.CacheVolumeCleanupWorker do
  @moduledoc false
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Tuist.Runners.CacheVolumes

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"action" => "evict"}}) do
    with {:ok, _count} <- CacheVolumes.expire_inactive(), do: :ok
  end

  def perform(_job), do: CacheVolumes.prune_history()
end
