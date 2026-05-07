defmodule Tuist.Kura.Workers.RolloutWorker do
  @moduledoc """
  Executes a single Kura deployment record through `Tuist.Kura.Provisioner`.

  Intentionally thin: load the deployment record and parent server,
  mark `:running`, hand it to the provisioner, translate the outcome
  into row state. Provisioner-specific machinery (Helm shells, Kubernetes
  API calls, controller status polling) lives behind the behaviour; this
  worker has no opinion about how the rollout happens.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Kura
  alias Tuist.Kura.Deployment
  alias Tuist.Kura.Provisioner
  alias Tuist.Kura.Server
  alias Tuist.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"deployment_id" => id, "account_id" => account_id}}) do
    case Kura.get_deployment(account_id, id) do
      {:error, :not_found} ->
        Logger.warning("[Kura.RolloutWorker] deployment #{id} not found")
        :ok

      {:ok, %Deployment{status: :running} = deployment} ->
        fail_running(deployment)
        :ok

      {:ok, %Deployment{status: status}} when status in [:succeeded, :failed, :cancelled] ->
        Logger.info("[Kura.RolloutWorker] deployment #{id} already in #{status}")
        :ok

      {:ok, %Deployment{} = deployment} ->
        execute(deployment)
    end
  end

  defp fail_running(%Deployment{} = deployment) do
    deployment = Repo.preload(deployment, :kura_server)
    fail(deployment, deployment.kura_server, "deployment was already running; re-trigger manually")
  end

  defp execute(%Deployment{} = deployment) do
    deployment = Repo.preload(deployment, kura_server: :account)

    case deployment.kura_server do
      nil -> fail(deployment, nil, "deployment has no parent kura_server")
      %Server{status: status} = server when status in [:destroying, :destroyed] -> cancel(deployment, server)
      %Server{} = server -> roll(deployment, server)
    end
  end

  defp cancel(deployment, %Server{} = server) do
    cancel(deployment, "server #{server.id} is #{server.status}; skipping rollout")
  end

  defp cancel(deployment, message) do
    {:ok, _} = Kura.mark_cancelled(deployment, message)
    :ok
  end

  defp roll(deployment, %Server{} = server) do
    {:ok, deployment} = Kura.mark_running(deployment)

    inputs = %{
      image_tag: deployment.image_tag,
      account: server.account,
      server: server
    }

    case Provisioner.rollout(server, inputs) do
      :ok ->
        case Kura.activate_server(server, deployment.image_tag) do
          {:ok, _} ->
            {:ok, _} = Kura.mark_succeeded(deployment)
            :ok

          {:error, status} when status in [:server_destroying, :server_destroyed] ->
            cancel(deployment, "server #{server.id} became #{server_status(status)} during rollout; skipping activation")

          {:error, reason} ->
            fail(deployment, server, reason)
        end

      {:error, :not_found} ->
        fail(deployment, server, "region #{server.region} is no longer in the catalog")

      {:error, reason} ->
        fail(deployment, server, reason)
    end
  end

  defp fail(deployment, server, reason) do
    message = if is_binary(reason), do: reason, else: inspect(reason)
    {:ok, _} = Kura.mark_failed(deployment, message)
    if server, do: Kura.fail_server(server)
    {:error, message}
  end

  defp server_status(:server_destroying), do: "destroying"
  defp server_status(:server_destroyed), do: "destroyed"
end
