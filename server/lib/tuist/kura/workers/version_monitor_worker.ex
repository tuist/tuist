defmodule Tuist.Kura.Workers.VersionMonitorWorker do
  @moduledoc """
  Watches for newly published Kura releases and schedules account
  server rollouts when their running version is behind.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Kura

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case Kura.schedule_latest_version_deployments() do
      {:ok, deployments} ->
        Logger.info("[Kura.VersionMonitorWorker] scheduled #{length(deployments)} Kura deployment(s)")
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end
end
