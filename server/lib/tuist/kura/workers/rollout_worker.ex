defmodule Tuist.Kura.Workers.RolloutWorker do
  @moduledoc """
  Executes a single Kura deployment by dispatching to the region's
  provider.

  Intentionally thin: load the deployment + parent server, mark
  `:running`, ask the provider to roll out, translate the outcome
  into row state. Provider-specific machinery (helm shells, log
  streaming, kubeconfig discovery) lives behind `Tuist.Kura.Provider`;
  the control plane has no opinion about how the rollout happens.

  Stdout/stderr the provider produces are streamed into ClickHouse via
  the per-deployment log sink so /ops can tail in real time.
  Concurrency is capped at 1 by the `:kura_rollout` queue.
  """
  use Oban.Worker, queue: :kura_rollout, max_attempts: 1

  alias Tuist.Kura
  alias Tuist.Kura.KuraDeployment
  alias Tuist.Kura.KuraServer
  alias Tuist.Kura.Provider
  alias Tuist.Kura.Regions
  alias Tuist.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"deployment_id" => id}}) do
    case Repo.get(KuraDeployment, id) do
      nil ->
        Logger.warning("[Kura.RolloutWorker] deployment #{id} not found")
        :ok

      %KuraDeployment{status: :running} = deployment ->
        # A retry picked up a deployment we'd already started. The
        # cluster-side rollout is idempotent at steady state, but we
        # fail explicitly so the operator notices.
        {:ok, _} = Kura.mark_failed(deployment, "deployment was already running; re-trigger manually")
        :ok

      %KuraDeployment{status: status} when status in [:succeeded, :failed, :cancelled] ->
        Logger.info("[Kura.RolloutWorker] deployment #{id} already in #{status}")
        :ok

      %KuraDeployment{} = deployment ->
        execute(deployment)
    end
  end

  defp execute(%KuraDeployment{} = deployment) do
    deployment = Repo.preload(deployment, [:account, :kura_server])

    case resolve_target(deployment) do
      {:ok, server, region} -> roll(deployment, server, region)
      {:error, message} -> fail(deployment, deployment.kura_server, message)
    end
  end

  defp resolve_target(%KuraDeployment{kura_server: nil}) do
    {:error, "deployment has no parent kura_server"}
  end

  defp resolve_target(%KuraDeployment{kura_server: %KuraServer{region: region_id} = server}) do
    case Regions.get(region_id) do
      nil -> {:error, "region #{region_id} is no longer in the catalog"}
      region -> {:ok, server, region}
    end
  end

  defp roll(deployment, server, region) do
    {:ok, deployment} = Kura.mark_running(deployment)

    inputs = %{
      image_tag: deployment.image_tag,
      account: deployment.account,
      server: server,
      region: region,
      on_log_line: log_sink(deployment.id)
    }

    case Provider.rollout(server, inputs) do
      :ok ->
        {:ok, _} = Kura.mark_succeeded(deployment)
        Kura.activate_server(server, deployment.image_tag)
        :ok

      {:error, reason} ->
        fail(deployment, server, reason)
    end
  end

  defp fail(deployment, server, reason) do
    message = if is_binary(reason), do: reason, else: inspect(reason)
    # Synthetic log line so /ops shows the reason instead of an empty terminal.
    {:ok, _} = Kura.append_log_lines(deployment.id, [{1, :stderr, message}])
    {:ok, _} = Kura.mark_failed(deployment, message)
    if server, do: Kura.fail_server(server)
    {:error, message}
  end

  # Returns a 2-arity callback the provider invokes per stdout/stderr
  # line. The callback batches into ClickHouse with a monotonically
  # increasing sequence so /ops's tail order is stable.
  defp log_sink(deployment_id) do
    Process.put(:kura_log_sequence, 0)

    fn line, stream ->
      {:ok, _} = Kura.append_log_lines(deployment_id, [{next_sequence(), stream, line}])
      :ok
    end
  end

  defp next_sequence do
    seq = Process.get(:kura_log_sequence, 0) + 1
    Process.put(:kura_log_sequence, seq)
    seq
  end
end
