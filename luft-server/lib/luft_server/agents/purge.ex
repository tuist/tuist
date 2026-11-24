defmodule LuftServer.Agents.Purge do
  @moduledoc """
  Deletes journals and then tombstoned session rows, in batches of 100.
  Owners mark `deleted_at` and clear `wanted` transactionally when deleted.
  Waits one minute after the last lease expiry (or deletion if never hosted)
  so a host has time to notice. Failed deletes retain the row for retry.
  Call `run/0` periodically; no job scheduler is required by this context.
  """
  import Ecto.Query

  alias LuftServer.Agents.SessionStore
  alias LuftServer.Repo

  require Logger

  def run do
    from(s in "agent_sessions",
      where:
        not is_nil(s.deleted_at) and
          coalesce(s.lease_expires_at, s.deleted_at) <
            fragment("CURRENT_TIMESTAMP - interval '1 minute'"),
      order_by: s.deleted_at,
      limit: 100,
      select: {s.id, s.kind}
    )
    |> Repo.all()
    |> Enum.filter(&purged?/1)
    |> Enum.map(&elem(&1, 0))
    |> then(
      &Repo.delete_all(
        from(s in "agent_sessions", where: s.id in ^&1 and not is_nil(s.deleted_at))
      )
    )

    :ok
  end

  defp purged?({id, kind}) do
    case SessionStore.delete(kind, id) do
      :ok ->
        true

      {:error, reason} ->
        Logger.warning("failed to delete stored agent session #{kind}/#{id}: #{inspect(reason)}")
        false
    end
  end
end
