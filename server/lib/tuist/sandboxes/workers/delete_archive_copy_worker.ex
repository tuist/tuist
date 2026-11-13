defmodule Tuist.Sandboxes.Workers.DeleteArchiveCopyWorker do
  @moduledoc """
  Deletes unreferenced archive migration copies after existing signed restore
  URLs have expired. Scheduled before copying for abandoned destinations, and
  transactionally with the route switch for retired rack objects. Failures
  snooze rather than exhausting the erasure obligation or dropping rack-byte
  accounting. The encrypted storage actor survives account deletion.
  """
  use Oban.Worker, queue: :sandbox_archives, max_attempts: 20

  alias Tuist.Sandboxes.Archives

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    case Archives.delete_archive_copy(args) do
      :ok -> :ok
      {:error, _reason} -> {:snooze, 300}
    end
  rescue
    # Don't persist credential-bearing storage errors in Oban's errors column.
    _ -> {:snooze, 300}
  end
end
