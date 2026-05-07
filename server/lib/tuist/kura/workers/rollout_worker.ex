defmodule Tuist.Kura.Workers.RolloutWorker do
  @moduledoc """
  Executes a single Kura deployment record through `Tuist.Kura.Provisioner`.

  Intentionally thin: load the deployment record and parent server, mark
  `:running`, and apply the desired `KuraInstance`. Readiness is observed
  asynchronously by `Tuist.Kura.Reconciler`, so this worker never waits on
  Kubernetes rollout status.
  """
  use Oban.Worker, queue: :kura_rollout, max_attempts: 1

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

      {:ok, %Deployment{status: status}} when status in [:succeeded, :failed, :cancelled] ->
        Logger.info("[Kura.RolloutWorker] deployment #{id} already in #{status}")
        :ok

      {:ok, %Deployment{} = deployment} ->
        execute(deployment)
    end
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
    with {:ok, deployment} <- ensure_running(deployment) do
      inputs = %{
        image_tag: deployment.image_tag,
        account: server.account,
        server: server
      }

      case Provisioner.rollout(server, inputs) do
        :ok ->
          :ok

        {:error, :not_found} ->
          fail(deployment, server, "region #{server.region} is no longer in the catalog")

        {:error, reason} ->
          fail(deployment, server, reason)
      end
    end
  end

  defp ensure_running(%Deployment{status: :running} = deployment), do: {:ok, deployment}
  defp ensure_running(%Deployment{} = deployment), do: Kura.mark_running(deployment)

  defp fail(deployment, server, reason) do
    message = if is_binary(reason), do: reason, else: inspect(reason)
    {:ok, _} = Kura.mark_failed(deployment, message)
    if server, do: Kura.fail_server(server)
    {:error, message}
  end
end
