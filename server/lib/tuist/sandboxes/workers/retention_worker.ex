defmodule Tuist.Sandboxes.Workers.RetentionWorker do
  @moduledoc """
  Deletes sandboxes that have been paused, or errored, for longer than
  the retention window. Either holds its memory image, rootfs and
  workspace on the node's disk, and its reservation against the node's
  disk budget, indefinitely otherwise; a session that comes back after
  its sandbox is gone gets a fresh one with the repository staged again.
  Linux Amp Orbs are excluded: Amp owns their lifecycle, they retain their
  disks until an explicit delete (or deletion of the owning account), and
  the archive tier moves paused ones off their nodes. macOS Orbs have no
  archive tier and share the Mac hosts' disks with CI, so they are deleted
  after seven days paused or errored. Amp's contract allows it: the thread's
  next message spawns a fresh Orb and Amp sets the repository up again.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Sandboxes

  require Logger

  @retention_days 14
  @macos_orb_retention_days 7

  def retention_days, do: @retention_days

  @impl Oban.Worker
  def perform(_job) do
    now = DateTime.utc_now()

    Enum.each(
      Sandboxes.list_sandboxes_idle_before(DateTime.add(now, -@retention_days, :day)) ++
        Sandboxes.list_sandboxes_idle_before(DateTime.add(now, -@macos_orb_retention_days, :day), :macos),
      fn sandbox ->
        case Sandboxes.delete(sandbox) do
          {:ok, _deleted} ->
            Logger.info("sandboxes: deleted a sandbox idle past retention",
              sandbox_id: sandbox.id,
              node: sandbox.node_name,
              state: sandbox.state,
              paused_at: sandbox.paused_at
            )

          {:error, reason} ->
            Logger.warning("sandboxes: failed to delete a sandbox idle past retention",
              sandbox_id: sandbox.id,
              node: sandbox.node_name,
              reason: inspect(reason)
            )
        end
      end
    )

    :ok
  end
end
