defmodule Tuist.Sandboxes.Workers.PauseRestoredOrbWorker do
  @moduledoc """
  Finishes an Amp pause the node refused because the Orb's warm restore was
  still loading its disks (`Tuist.Sandboxes.AmpOrbs.pause_after_restore/2`).
  Amp does not send the pause again, and an Orb whose services keep its CPU
  busy never reaches the idle pause, so without this it ran, holding its
  node's memory, until its thread's next turn (in production, 2026-11-26,
  for days). Retries every minute while the disks load, for an hour.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [keys: [:sandbox_id], states: [:available, :scheduled, :retryable]]

  alias Tuist.Sandboxes.AmpOrbs

  require Logger

  @retry_seconds 60
  @give_up_after_seconds 3600

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"sandbox_id" => sandbox_id, "residency_epoch" => epoch}, inserted_at: inserted_at}) do
    case AmpOrbs.pause_after_restore(sandbox_id, epoch) do
      {:ok, _paused_or_skipped} ->
        :ok

      {:error, reason} when reason in [:restoring, :locked] ->
        if DateTime.diff(DateTime.utc_now(), inserted_at) < @give_up_after_seconds do
          {:snooze, @retry_seconds}
        else
          Logger.warning("sandboxes: gave up pausing a restored Orb", sandbox_id: sandbox_id, reason: reason)
          :ok
        end

      {:error, reason} ->
        Logger.warning("sandboxes: pausing a restored Orb failed", sandbox_id: sandbox_id, reason: inspect(reason))
        {:error, reason}
    end
  end
end
