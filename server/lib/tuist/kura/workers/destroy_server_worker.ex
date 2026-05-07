defmodule Tuist.Kura.Workers.DestroyServerWorker do
  @moduledoc """
  Starts Kura server teardown through `Tuist.Kura.Provisioner`.

  `account_cache_endpoints` is removed up-front by
  `Tuist.Kura.destroy_server/1` so the CLI stops resolving the URL the
  instant the row enters `:destroying` — even before the cluster-side
  teardown finishes.

  The worker only asks Kubernetes to delete the backing resource. The
  row stays `:destroying` until `Tuist.Kura.Reconciler` observes that the
  `KuraInstance` is gone and marks it `:destroyed`.
  """
  use Oban.Worker, queue: :kura_rollout, max_attempts: 5

  alias Tuist.Kura
  alias Tuist.Kura.Provisioner
  alias Tuist.Kura.Server

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"server_id" => id, "account_id" => account_id}}) do
    case Kura.get_server(account_id, id) do
      nil ->
        Logger.warning("[Kura.DestroyServerWorker] server #{id} not found")
        :ok

      %Server{status: :destroyed} ->
        :ok

      %Server{status: status} when status != :destroying ->
        Logger.info("[Kura.DestroyServerWorker] server #{id} is #{status}; skipping destroy")
        :ok

      %Server{status: :destroying} = server ->
        destroy_backing_resource(server)
    end
  end

  defp destroy_backing_resource(server) do
    case Provisioner.destroy(server) do
      :ok -> :ok
      {:error, reason} -> {:error, {:provisioner_destroy_failed, reason}}
    end
  end
end
