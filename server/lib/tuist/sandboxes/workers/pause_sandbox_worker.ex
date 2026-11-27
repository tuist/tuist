defmodule Tuist.Sandboxes.Workers.PauseSandboxWorker do
  @moduledoc """
  Pauses a sandbox once its worker has been gone for the grace period.

  Scheduled by `Tuist.Sandboxes.end_residency/1` with the residency
  epoch current at that moment; `Tuist.Sandboxes.pause_idle/2` checks it
  against the row under the sandbox's lock. A new residency bumps the epoch, so a
  job enqueued for an earlier exit finds a mismatch and does nothing;
  the newer exit schedules its own job. Uniqueness is keyed on the
  sandbox so at most one pause is pending per sandbox, with the newest
  exit replacing the args and schedule of a pending one.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:sandbox_id], states: [:available, :scheduled], period: :infinity]

  alias Tuist.Sandboxes

  require Logger

  @disks_loading_snooze_seconds 60
  @busy_snooze_seconds 15

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"sandbox_id" => sandbox_id, "residency_epoch" => epoch}}) do
    case Sandboxes.pause_idle(sandbox_id, residency_epoch: epoch) do
      {:ok, _paused_or_skipped} ->
        :ok

      {:error, :not_found} ->
        :ok

      # A warm restore streams its disks from the archive for minutes after
      # the guest runs, past the retries, and the node refuses a pause until
      # they are whole. `memory_loaded` schedules the pause again once they
      # are; the snooze still pauses the sandbox if that event is lost, and a
      # newer residency's epoch turns it into a no-op.
      {:error, "sandbox disks are still loading from its archive" <> _id} ->
        Logger.info("sandboxes: scheduled pause waits for a restore's disks", sandbox_id: sandbox_id)
        {:snooze, @disks_loading_snooze_seconds}

      # The node refuses to pause while an exec is in flight. An exec takes no
      # residency, and its caller can give up before the node does (an Amp
      # Orb's bootstrap timing out ends the turn and pauses at once on a shared
      # node while the node still runs the exec), so retrying soon pauses it.
      # Failing instead spent the job's three attempts and could leave the
      # sandbox running with nothing left to pause it.
      {:error, "sandbox has a worker or exec running" <> _id} ->
        Logger.info("sandboxes: scheduled pause waits for an exec to end", sandbox_id: sandbox_id)
        {:snooze, @busy_snooze_seconds}

      {:error, reason} ->
        Logger.warning("sandboxes: scheduled pause failed", sandbox_id: sandbox_id, reason: inspect(reason))
        {:error, reason}
    end
  end
end
