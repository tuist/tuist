defmodule Tuist.Kura.Workers.DestroyServerWorker do
  @moduledoc """
  Tears down a Kura server by dispatching to the region's provider,
  then marks the row `:destroyed`.

  The `account_cache_endpoints` row is removed up-front by
  `Tuist.Kura.destroy_server/1` so the CLI stops resolving the URL
  immediately, even before the cluster-side teardown finishes.

  Failures here are logged but do not block the row's transition to
  `:destroyed`. A stuck `:destroying` row would block re-using the
  (account, region) pair, which is worse than an orphaned backing
  resource that an operator can clean up manually. Provider impls
  should mirror this and prefer returning `:ok` over surfacing a
  permanent error.
  """
  use Oban.Worker, queue: :kura_rollout, max_attempts: 1

  alias Tuist.Kura
  alias Tuist.Kura.KuraServer
  alias Tuist.Kura.Provider
  alias Tuist.Kura.Regions
  alias Tuist.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"server_id" => id}}) do
    case Repo.get(KuraServer, id) do
      nil ->
        Logger.warning("[Kura.DestroyServerWorker] server #{id} not found")
        :ok

      %KuraServer{status: :destroyed} ->
        :ok

      %KuraServer{} = server ->
        execute(server)
    end
  end

  defp execute(%KuraServer{} = server) do
    case Regions.get(server.region) do
      nil ->
        Logger.warning(
          "[Kura.DestroyServerWorker] region #{server.region} no longer in catalog; marking destroyed anyway"
        )

        {:ok, _} = Kura.mark_destroyed(server)
        :ok

      %Regions{} ->
        case Provider.destroy(server) do
          :ok -> :ok
          {:error, reason} -> Logger.warning("[Kura.DestroyServerWorker] provider destroy failed: #{inspect(reason)}")
        end

        {:ok, _} = Kura.mark_destroyed(server)
        :ok
    end
  end
end
