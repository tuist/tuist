defmodule Tuist.Kura.Workers.RolloutWorker do
  @moduledoc """
  Executes a single Kura deployment record through `Tuist.Kura.Provisioner`.

  Intentionally thin: load the deployment record and parent server,
  mark `:running`, hand it to the provisioner, translate the outcome
  into row state. Provisioner-specific machinery (helm shells, log
  streaming, kubeconfig discovery) lives behind the behaviour; this
  worker has no opinion about how the rollout happens.

  Stdout/stderr from the provisioner streams into ClickHouse via the
  per-deployment log sink so /ops can tail in real time. Concurrency
  is capped at 1 by the `:kura_rollout` queue.
  """
  use Oban.Worker, queue: :kura_rollout, max_attempts: 1

  alias Tuist.Kura
  alias Tuist.Kura.KuraDeployment
  alias Tuist.Kura.KuraServer
  alias Tuist.Kura.Provisioner
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

    case deployment.kura_server do
      nil -> fail(deployment, nil, "deployment has no parent kura_server")
      %KuraServer{} = server -> roll(deployment, server)
    end
  end

  defp roll(deployment, %KuraServer{} = server) do
    {:ok, deployment} = Kura.mark_running(deployment)

    inputs = %{
      image_tag: deployment.image_tag,
      account: deployment.account,
      server: server,
      on_log_line: log_sink(deployment.id)
    }

    case Provisioner.rollout(server, inputs) do
      :ok ->
        {:ok, _} = Kura.mark_succeeded(deployment)
        Kura.activate_server(server, deployment.image_tag)
        :ok

      {:error, :not_found} ->
        fail(deployment, server, "region #{server.region} is no longer in the catalog")

      {:error, reason} ->
        fail(deployment, server, reason)
    end
  end

  defp fail(deployment, server, reason) do
    message = if is_binary(reason), do: reason, else: inspect(reason)
    # Synthetic log line so /ops shows the reason instead of an empty terminal.
    {:ok, _} = Kura.append_log_lines(deployment.id, [{next_sequence(), :stderr, message}])
    {:ok, _} = Kura.mark_failed(deployment, message)
    if server, do: Kura.fail_server(server)
    {:error, message}
  end

  # Returns a 2-arity callback the provisioner invokes per stdout/stderr
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
