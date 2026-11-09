defmodule Tuist.Sandboxes.Workers.ArchiveDiskSnapshotWorker do
  @moduledoc """
  Uploads one ready disk snapshot to object storage
  (`Tuist.Sandboxes.Archives.archive_disk_snapshot/1`), so any node can
  create a sandbox from it. Queued after each save
  (`Archives.queue_disk_snapshot/1`) and by the hourly archive run for
  snapshots whose last attempt failed more than six hours ago. A failed
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

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"disk_snapshot_id" => id}}) do
    # A snapshot deleted or superseded meanwhile never loads.
    with %DiskSnapshot{} = snapshot <- Repo.get(DiskSnapshot, id) do
      Archives.archive_disk_snapshot(snapshot)
    end

    :ok
  end
end
