defmodule Tuist.Kura.Workers.DestroyServerWorker do
  @moduledoc """
  Tears down a Kura server through `Tuist.Kura.Provisioner` and marks the
  row `:destroyed`.

  `account_cache_endpoints` is removed up-front by
  `Tuist.Kura.destroy_server/1` so the CLI stops resolving the URL the
  instant the row enters `:destroying` — even before the cluster-side
  teardown finishes.

  Failures here are logged but never block the row's transition to
  `:destroyed`. A stuck `:destroying` row would block re-using the
  `(account, region)` pair, which is worse than an orphaned backing
  resource that an operator can clean up manually.
  """
  use Oban.Worker, queue: :kura_rollout, max_attempts: 1

  alias Tuist.Kura
  alias Tuist.Kura.Provisioner
  alias Tuist.Kura.KuraServer
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
        log_outcome(server, Provisioner.destroy(server))
        {:ok, _} = Kura.mark_destroyed(server)
        :ok
    end
  end

  defp log_outcome(_server, :ok), do: :ok

  defp log_outcome(%KuraServer{region: region}, {:error, :not_found}) do
    Logger.warning("[Kura.DestroyServerWorker] region #{region} not in catalog; marking destroyed anyway")
  end

  defp log_outcome(_server, {:error, reason}) do
    Logger.warning("[Kura.DestroyServerWorker] provisioner destroy failed: #{inspect(reason)}")
  end
end
