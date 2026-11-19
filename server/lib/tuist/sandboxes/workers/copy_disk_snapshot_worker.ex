defmodule Tuist.Sandboxes.Workers.CopyDiskSnapshotWorker do
  @moduledoc """
  Copies a popular archived disk snapshot onto other nodes
  (`Tuist.Sandboxes.DiskSnapshots.copy/1`), so its next spawns clone it
  where there is room instead of downloading it. Queued when a spawn missed
  every node holding the snapshot and when a snapshot finishes archiving
  (`DiskSnapshots.queue_copies/1`). One job per snapshot at a time; a copy
  that fails is retried by the next miss, not by Oban.
  """
  use Oban.Worker,
    queue: :sandbox_snapshot_copies,
    max_attempts: 1,
    unique: [keys: [:disk_snapshot_id], states: [:available, :scheduled, :executing], period: :infinity]

  alias Tuist.Repo
  alias Tuist.Sandboxes.DiskSnapshot
  alias Tuist.Sandboxes.DiskSnapshots

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"disk_snapshot_id" => id}}) do
    with %DiskSnapshot{} = snapshot <- Repo.get(DiskSnapshot, id), do: DiskSnapshots.copy(snapshot)
    :ok
  end
end
