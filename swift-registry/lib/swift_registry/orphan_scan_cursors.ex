defmodule SwiftRegistry.OrphanScanCursors do
  @moduledoc false

  alias SwiftRegistry.OrphanScanCursor
  alias SwiftRegistry.Repo

  require Logger

  @singleton_id 1

  def get_cursor do
    Repo.get(OrphanScanCursor, @singleton_id)
  end

  def update_cursor(cursor_path) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    %OrphanScanCursor{id: @singleton_id}
    |> OrphanScanCursor.changeset(%{cursor_path: cursor_path})
    |> Repo.insert(
      on_conflict: [set: [cursor_path: cursor_path, updated_at: now]],
      conflict_target: :id
    )
    |> log_persist_error("update orphan scan cursor")
  end

  def reset_cursor do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    %OrphanScanCursor{id: @singleton_id}
    |> OrphanScanCursor.changeset(%{cursor_path: nil, last_completed_at: now})
    |> Repo.insert(
      on_conflict: [set: [cursor_path: nil, last_completed_at: now, updated_at: now]],
      conflict_target: :id
    )
    |> log_persist_error("reset orphan scan cursor")
  end

  defp log_persist_error({:ok, _}, _label), do: :ok

  defp log_persist_error({:error, reason}, label) do
    Logger.warning("Failed to #{label}: #{inspect(reason)}")
    :ok
  end
end
