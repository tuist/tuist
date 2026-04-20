defmodule Tuist.Runners.Workers.DeprovisionOrchardWorkerWorker do
  @moduledoc """
  Releases a Scaleway bare-metal Mac that was previously provisioned as an
  Orchard worker host. Deletes the Scaleway server and marks the OrchardWorker
  record as `:terminated`.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Tuist.Runners
  alias Tuist.Scaleway
  alias Tuist.Scaleway.Client, as: ScalewayClient

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"orchard_worker_id" => worker_id}}) do
    with {:ok, worker} <- Runners.get_orchard_worker(worker_id),
         {:ok, _} <- Runners.update_orchard_worker(worker, %{status: :terminating}),
         {:ok, config} <- Scaleway.config(),
         :ok <- delete_server(config, worker),
         {:ok, _worker} <-
           Runners.update_orchard_worker(worker, %{
             status: :terminated,
             terminated_at: DateTime.truncate(DateTime.utc_now(), :second)
           }) do
      :ok
    else
      {:error, :not_found} ->
        Logger.warning("OrchardWorker #{worker_id} not found during deprovisioning")
        :ok

      {:error, reason} ->
        Logger.error("Failed to deprovision OrchardWorker #{worker_id}: #{inspect(reason)}")
        mark_failed(worker_id, reason)
        {:error, reason}
    end
  end

  defp delete_server(_config, %{scaleway_server_id: nil}), do: :ok

  defp delete_server(config, worker) do
    ScalewayClient.delete_server(config, worker.scaleway_zone, worker.scaleway_server_id)
  end

  defp mark_failed(worker_id, reason) do
    case Runners.get_orchard_worker(worker_id) do
      {:ok, worker} ->
        Runners.update_orchard_worker(worker, %{
          status: :failed,
          error_message: format_reason(reason)
        })

      _ ->
        :ok
    end
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
