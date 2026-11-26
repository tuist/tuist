defmodule Tuist.Snapshots.Workers.RecoverStalledBuildsWorker do
  @moduledoc """
  Every minute, requeues snapshot comparisons whose job stopped beating while
  Oban still records it as executing (`Tuist.Snapshots.recover_stalled_builds/1`).
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Snapshots

  @impl Oban.Worker
  def perform(_job) do
    Snapshots.recover_stalled_builds()
    :ok
  end
end
