defmodule Tuist.Sandboxes.Workers.RefreshMacSnapshotsWorker do
  @moduledoc """
  Rebuilds the macOS repository snapshots in use whose default branch moved
  (`Tuist.Sandboxes.ClaudeCodeSnapshots.refresh_mac_snapshots/0`).
  """
  use Oban.Worker, queue: :default, max_attempts: 1, unique: [period: 300]

  alias Tuist.Sandboxes.ClaudeCodeSnapshots

  @impl Oban.Worker
  def perform(_job), do: ClaudeCodeSnapshots.refresh_mac_snapshots()
end
