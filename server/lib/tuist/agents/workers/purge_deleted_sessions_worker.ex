defmodule Tuist.Agents.Workers.PurgeDeletedSessionsWorker do
  @moduledoc """
  Deletes the stored conversation of agent sessions whose owner was deleted,
  then their rows.

  Deleting a thread marks its session (`deleted_at`) from a database trigger,
  which cannot reach object storage. A session a host still holds, or held
  within the last minute, is left for a later pass, so a host that has not
  yet noticed cannot write objects after they were deleted.
  """
  use Oban.Worker, queue: :threads, max_attempts: 3

  import Ecto.Query

  alias Tuist.Agents.SessionStore
  alias Tuist.Repo

  require Logger

  @batch 100

  @impl true
  def perform(_job) do
    from(s in "agent_sessions",
      where:
        not is_nil(s.deleted_at) and
          coalesce(s.lease_expires_at, s.deleted_at) < fragment("CURRENT_TIMESTAMP - interval '1 minute'"),
      order_by: s.deleted_at,
      limit: @batch,
      select: {s.id, s.kind}
    )
    |> Repo.all()
    |> Enum.filter(&purged?/1)
    |> Enum.map(&elem(&1, 0))
    |> then(&Repo.delete_all(from(s in "agent_sessions", where: s.id in ^&1 and not is_nil(s.deleted_at))))

    :ok
  end

  # A session whose objects could not all be deleted keeps its row, so the
  # next pass tries again.
  defp purged?({id, kind}) do
    case SessionStore.delete(kind, id) do
      :ok ->
        true

      {:error, reason} ->
        Logger.warning("failed to delete the stored agent session #{kind}/#{id}: #{inspect(reason)}")
        false
    end
  end
end
