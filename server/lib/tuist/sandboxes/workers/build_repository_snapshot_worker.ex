defmodule Tuist.Sandboxes.Workers.BuildRepositorySnapshotWorker do
  @moduledoc """
  Follows one Claude Code repository snapshot build
  (`Tuist.Sandboxes.ClaudeCodeSnapshots.advance/1`) until it is saved or
  fails. Snoozes between checks; snoozing does not use up attempts. A build
  this worker gives up on is cleaned up by
  `Tuist.Sandboxes.DiskSnapshots.delete_expired/0`.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [keys: [:disk_snapshot_id], states: [:available, :scheduled], period: :infinity]

  alias Tuist.Repo
  alias Tuist.Sandboxes.ClaudeCodeSnapshots
  alias Tuist.Sandboxes.DiskSnapshot

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"disk_snapshot_id" => id}}) do
    case Repo.get(DiskSnapshot, id) do
      %DiskSnapshot{} = build -> ClaudeCodeSnapshots.advance(build)
      nil -> :ok
    end
  end
end
