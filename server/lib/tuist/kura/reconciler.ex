defmodule Tuist.Kura.Reconciler do
  @moduledoc """
  Primary reconciliation loop for Kura servers.

  Desired state lives in Postgres (`kura_servers` and `kura_deployments`)
  plus the latest released Kura runtime image tag. Actual state lives in
  `KuraInstance.status`, owned by the Go controller. This loop closes
  the gap periodically: it schedules image drift, applies pending
  deployments, mirrors observed readiness back into Postgres, and
  finalises destroys after the custom resource disappears.

  User actions only mutate Postgres. If a BEAM dies mid-action, this
  loop observes the same rows on the next tick and converges again.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query

  alias Tuist.Kura
  alias Tuist.Kura.Deployment
  alias Tuist.Kura.Provisioner
  alias Tuist.Kura.Server
  alias Tuist.Repo

  require Logger

  @deployment_statuses [:pending, :running]
  # Hard ceiling on how much converge work the reconciler does in one
  # tick. The cron fires every 30 s; bigger fan-outs are rare enough in
  # practice that one or two extra ticks are fine, and the ceiling
  # guards against a runaway query if a regression ever leaks
  # `:running` rows.
  @reconcile_batch_size 200

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    reconcile()
  end

  def reconcile do
    with {:ok, scheduled} <- Kura.schedule_runtime_image_deployments() do
      log_scheduled_deployments(scheduled)
      reconcile_destroying_servers()
      reconcile_deployments()
    end
  end

  defp log_scheduled_deployments([]), do: :ok

  defp log_scheduled_deployments(deployments) do
    Logger.info("[Kura.Reconciler] scheduled #{length(deployments)} runtime image deployment(s)")
    :ok
  end

  defp reconcile_destroying_servers do
    Server
    |> where([s], s.status == :destroying)
    |> order_by([s], asc: s.updated_at, asc: s.id)
    |> limit(^@reconcile_batch_size)
    |> Repo.all()
    |> Enum.each(&reconcile_destroying_server/1)

    :ok
  end

  defp reconcile_destroying_server(%Server{} = server) do
    case Provisioner.current_image_tag(server) do
      {:error, :not_found} ->
        {:ok, _} = Kura.mark_destroyed(server)
        :ok

      {:ok, _image_tag} ->
        case Provisioner.destroy(server) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.warning("[Kura.Reconciler] destroy failed for server #{server.id}: #{inspect(reason)}")
            :ok
        end

      {:error, reason} ->
        Logger.warning("[Kura.Reconciler] could not observe destroying server #{server.id}: #{inspect(reason)}")
        :ok
    end
  end

  defp reconcile_deployments do
    Enum.each(latest_open_deployments(), &reconcile_deployment/1)
    :ok
  end

  defp latest_open_deployments do
    Deployment
    |> where([d], d.status in ^@deployment_statuses)
    |> join(:inner, [d], s in assoc(d, :kura_server))
    |> order_by([d, _s], desc: d.inserted_at, desc: d.id)
    |> limit(^@reconcile_batch_size)
    |> preload([_d, s], kura_server: {s, :account})
    |> Repo.all()
    |> Enum.uniq_by(& &1.kura_server_id)
  end

  defp reconcile_deployment(%Deployment{kura_server: %Server{status: status} = server} = deployment)
       when status in [:destroying, :destroyed] do
    cancel(deployment, "server #{server.id} is #{server.status}; skipping rollout")
  end

  defp reconcile_deployment(%Deployment{kura_server: %Server{} = server} = deployment) do
    case Provisioner.current_image_tag(server) do
      {:ok, image_tag} when image_tag == deployment.image_tag ->
        activate_and_mark_succeeded(deployment, server)

      {:ok, _other_image_tag} ->
        apply_deployment(deployment, server)

      {:error, :not_found} ->
        apply_deployment(deployment, server)

      {:error, reason} ->
        fail(deployment, server, reason)
    end
  end

  defp activate_and_mark_succeeded(%Deployment{} = deployment, %Server{} = server) do
    case Kura.activate_server(server, deployment.image_tag) do
      {:ok, _server} ->
        {:ok, _deployment} = Kura.mark_succeeded(deployment)
        :ok

      {:error, status} when status in [:server_destroying, :server_destroyed] ->
        cancel(deployment, "server #{server.id} became #{server_status(status)} during rollout; skipping activation")

      {:error, {:public_host_not_resolvable, host, reason}} ->
        # external-dns has not propagated yet. Leave the deployment in
        # `:running` so the next reconciler tick retries instead of
        # marking the server failed for what's a benign delay.
        Logger.info("[Kura.Reconciler] waiting on DNS for server #{server.id} (#{host}): #{inspect(reason)}")

        :ok

      {:error, {:public_endpoint_not_ready, host, reason}} ->
        Logger.info("[Kura.Reconciler] waiting on public endpoint for server #{server.id} (#{host}): #{inspect(reason)}")

        :ok

      {:error, reason} ->
        fail(deployment, server, reason)
    end
  end

  defp apply_deployment(%Deployment{} = deployment, %Server{} = server) do
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

  defp cancel(deployment, message) do
    {:ok, _} = Kura.mark_cancelled(deployment, message)
    :ok
  end

  defp fail(deployment, server, reason) do
    message = if is_binary(reason), do: reason, else: inspect(reason)

    capture_deploy_failure(deployment, server, message)

    {:ok, _} = Kura.mark_failed(deployment, message)
    if server, do: fail_or_reset_server(server)
    :ok
  end

  # A server that never reached `:active` has nothing serving traffic,
  # so resetting the row to `:destroyed` is safe and lets the UI render
  # the region as "Not deployed" for an immediate retry. An
  # already-active server keeps serving on the old image; we only flip
  # it to `:failed` so the failed drift is visible without tearing
  # down the working endpoint.
  defp fail_or_reset_server(%Server{status: :provisioning} = server), do: Kura.reset_server(server)
  defp fail_or_reset_server(%Server{} = server), do: Kura.fail_server(server)

  defp capture_deploy_failure(deployment, server, message) do
    Sentry.capture_message("Kura deploy failed",
      level: :error,
      extra: %{
        deployment_id: deployment.id,
        image_tag: deployment.image_tag,
        server_id: server && server.id,
        account_id: server && server.account_id,
        region: server && server.region,
        reason: message
      }
    )
  end

  defp server_status(:server_destroying), do: "destroying"
  defp server_status(:server_destroyed), do: "destroyed"
end
