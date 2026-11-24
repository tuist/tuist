defmodule Tuist.Sandboxes.Workers.PauseIdleOrbWorker do
  @moduledoc """
  Pauses a running Amp Orb whose guest has been quiet past the idle
  threshold (`Tuist.Sandboxes.AmpOrbs.pause_idle/2`). Node reports enqueue
  it, and the next report that still finds the Orb quiet enqueues it again
  when this run skipped it.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [keys: [:sandbox_id], states: [:available, :scheduled, :executing], period: :infinity]

  alias Tuist.Sandboxes.AmpOrbs

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"sandbox_id" => sandbox_id, "last_active_at" => last_active_at}}) do
    {:ok, last_active_at, 0} = DateTime.from_iso8601(last_active_at)

    case AmpOrbs.pause_idle(sandbox_id, last_active_at) do
      {:ok, _paused_or_skipped} ->
        :ok

      {:error, :locked} ->
        :ok

      # The node's socket went away (a daemon restart pauses or loses its
      # VMs); its next report settles the Orb's state and, if it still runs
      # quiet, enqueues this pause again.
      {:error, reason} when reason in [:node_disconnected, :not_connected] ->
        Logger.info("sandboxes: idle Orb pause interrupted by its node", sandbox_id: sandbox_id, reason: reason)
        :ok

      {:error, reason} ->
        Logger.warning("sandboxes: idle Orb pause failed", sandbox_id: sandbox_id, reason: inspect(reason))
        {:error, reason}
    end
  end
end
