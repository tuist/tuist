defmodule Tuist.Runners.Workers.ProvisionOrchardWorkerWorker do
  @moduledoc """
  Provisions a Scaleway bare-metal Mac and prepares it as an Orchard worker host.

  Lifecycle:
    1. Load OrchardWorker row, move to `:provisioning`.
    2. Create the Scaleway server via the Apple Silicon API.
    3. SSH in and run the provisioner (brew, tart, orchard CLI, kcpassword,
       auto-login, reboot).
    4. On success mark `:online`; on failure mark `:failed` with error.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Runners
  alias Tuist.Runners.OrchardWorkerProvisioner
  alias Tuist.Scaleway
  alias Tuist.Scaleway.Client, as: ScalewayClient

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"orchard_worker_id" => worker_id}}) do
    with {:ok, worker} <- Runners.get_orchard_worker(worker_id),
         {:ok, _} <- Runners.update_orchard_worker(worker, %{status: :provisioning}),
         {:ok, config} <- Scaleway.config(),
         {:ok, os_id} <- ScalewayClient.find_os_id(config, worker.scaleway_zone, worker.scaleway_os),
         {:ok, server} <- create_server(config, worker, os_id),
         {:ok, worker} <-
           Runners.update_orchard_worker(worker, %{
             scaleway_server_id: server["id"],
             ip_address: List.first(server["ip_addresses"] || []) || server["ip"]
           }),
         :ok <-
           OrchardWorkerProvisioner.provision(%{
             ip: worker.ip_address,
             ssh_user: server["ssh_username"] || "m1",
             sudo_password: server["sudo_password"]
           }),
         {:ok, _worker} <-
           Runners.update_orchard_worker(worker, %{
             status: :online,
             provisioned_at: DateTime.truncate(DateTime.utc_now(), :second)
           }) do
      :ok
    else
      {:error, reason} ->
        mark_failed(worker_id, reason)
        {:error, reason}
    end
  end

  defp create_server(config, worker, os_id) do
    ScalewayClient.create_server(config, %{
      name: worker.name,
      zone: worker.scaleway_zone,
      server_type: worker.scaleway_server_type,
      os_id: os_id
    })
  end

  defp mark_failed(worker_id, reason) do
    Logger.error("Orchard worker #{worker_id} provisioning failed: #{inspect(reason)}")

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
