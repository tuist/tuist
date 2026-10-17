defmodule Tuist.Sandboxes.Workers.RetentionWorker do
  @moduledoc """
  Deletes sandboxes that have been paused, or errored, for longer than
  the retention window. Either holds its memory image, rootfs and
  workspace on the node's disk, and its reservation against the node's
  disk budget, indefinitely otherwise; a session that comes back after
  its sandbox is gone gets a fresh one with the repository staged again.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Sandboxes

  require Logger

  @retention_days 14

  def retention_days, do: @retention_days

  @impl Oban.Worker
  def perform(_job) do
    cutoff = DateTime.add(DateTime.utc_now(), -@retention_days, :day)

    cutoff
    |> Sandboxes.list_sandboxes_idle_before()
    |> Enum.each(fn sandbox ->
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
    end)

    :ok
  end
end
