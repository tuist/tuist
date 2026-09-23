defmodule Tuist.Sandboxes.Workers.RetentionWorker do
  @moduledoc """
  Deletes sandboxes that have been paused for longer than the retention
  window. A paused sandbox holds its memory image, rootfs delta and
  workspace on the node's disk indefinitely otherwise; a session that
  comes back after its sandbox is gone gets a fresh one with the
  repository staged again.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Sandboxes

  require Logger

  @paused_retention_days 14

  def paused_retention_days, do: @paused_retention_days

  @impl Oban.Worker
  def perform(_job) do
    cutoff = DateTime.add(DateTime.utc_now(), -@paused_retention_days, :day)

    cutoff
    |> Sandboxes.list_sandboxes_paused_before()
    |> Enum.each(fn sandbox ->
      case Sandboxes.delete(sandbox) do
        {:ok, _deleted} ->
          Logger.info("sandboxes: deleted a sandbox paused past retention",
            sandbox_id: sandbox.id,
            node: sandbox.node_name,
            paused_at: sandbox.paused_at
          )

        {:error, reason} ->
          Logger.warning("sandboxes: failed to delete a sandbox paused past retention",
            sandbox_id: sandbox.id,
            node: sandbox.node_name,
            reason: inspect(reason)
          )
      end
    end)

    :ok
  end
end
