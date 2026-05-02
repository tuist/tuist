defmodule Tuist.Kura.Workers.DestroyServerWorker do
  @moduledoc """
  Tears down a Kura server through `Tuist.Kura.Provisioner` and marks the
  row `:destroyed`.

  `account_cache_endpoints` is removed up-front by
  `Tuist.Kura.destroy_server/1` so the CLI stops resolving the URL the
  instant the row enters `:destroying` — even before the cluster-side
  teardown finishes.

  The destroy is intentionally ordered as:

    1. tear down the backing resource through the provisioner
    2. mark the row `:destroyed`

  If either step fails, the worker returns an error to Oban and leaves
  the row in `:destroying` so retries can continue from the same state.
  `Tuist.Kura.Provisioner.destroy/2` is required to be idempotent so
  those retries are safe even when the backing resource was already
  removed.
  """
  use Oban.Worker, queue: :kura_rollout, max_attempts: 5

  alias Tuist.Kura
  alias Tuist.Kura.Provisioner
  alias Tuist.Kura.Server
  alias Tuist.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"server_id" => id}}) do
    case Repo.get(Server, id) do
      nil ->
        Logger.warning("[Kura.DestroyServerWorker] server #{id} not found")
        :ok

      %Server{status: :destroyed} ->
        :ok

      %Server{} = server ->
        with :ok <- destroy_backing_resource(server),
             {:ok, _} <- Kura.mark_destroyed(server) do
          :ok
        end
    end
  end

  defp destroy_backing_resource(server) do
    case Provisioner.destroy(server) do
      :ok -> :ok
      {:error, reason} -> {:error, {:provisioner_destroy_failed, reason}}
    end
  end
end
