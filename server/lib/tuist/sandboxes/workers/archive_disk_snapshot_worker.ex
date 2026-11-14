defmodule Tuist.Sandboxes.Workers.ArchiveDiskSnapshotWorker do
  @moduledoc """
  Uploads one ready disk snapshot to object storage
  (`Tuist.Sandboxes.Archives.archive_disk_snapshot/1`), so any node can
  create a sandbox from it. Queued after each save
  (`Archives.queue_disk_snapshot/1`) and by the minute archive run for
  snapshots whose last attempt failed more than five minutes ago. A failed
  upload is recorded on the row and retried that way, not by Oban. The
  upload claim on the row keeps two jobs off the same snapshot.
  """
  use Oban.Worker,
    queue: :sandbox_archives,
    max_attempts: 1,
    unique: [keys: [:disk_snapshot_id], states: [:available, :scheduled, :executing], period: :infinity]

  alias Tuist.Repo
  alias Tuist.Sandboxes.Archives
  alias Tuist.Sandboxes.DiskSnapshot
  alias Tuist.Sandboxes.DiskSnapshots

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"disk_snapshot_id" => id}}) do
    # A snapshot deleted or superseded meanwhile never loads.
    # A popular project's refreshed snapshot is copied out once it can be.
    with %DiskSnapshot{} = snapshot <- Repo.get(DiskSnapshot, id),
         {:ok, %DiskSnapshot{} = archived} <- Archives.archive_disk_snapshot(snapshot) do
      DiskSnapshots.queue_copies(archived)
    end

    :ok
  end
end
