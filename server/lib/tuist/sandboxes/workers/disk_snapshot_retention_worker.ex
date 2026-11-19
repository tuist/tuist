defmodule Tuist.Sandboxes.Workers.DiskSnapshotRetentionWorker do
  @moduledoc """
  Deletes disk snapshots nothing was created from for longer than Amp
  reuses a project snapshot, and saves that never finished. Each one
  reserves its full ceiling against its node's disk budget until then.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Sandboxes.DiskSnapshots

  @impl Oban.Worker
  def perform(_job) do
    DiskSnapshots.delete_expired()
    :ok
  end
end
