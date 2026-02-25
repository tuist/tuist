defmodule Cache.OrphanScanCursors do
  @moduledoc false

  alias Cache.OrphanScanCursor
  alias Cache.Repo

  @singleton_id 1

  def get_cursor do
    Repo.get(OrphanScanCursor, @singleton_id)
  end

  def update_cursor(cursor_path) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %OrphanScanCursor{id: @singleton_id}
    |> OrphanScanCursor.changeset(%{cursor_path: cursor_path})
    |> Repo.insert(
      on_conflict: [set: [cursor_path: cursor_path, updated_at: now]],
      conflict_target: :id
    )

    :ok
  end

  def reset_cursor do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %OrphanScanCursor{id: @singleton_id}
    |> OrphanScanCursor.changeset(%{cursor_path: nil, last_completed_at: now})
    |> Repo.insert(
      on_conflict: [set: [cursor_path: nil, last_completed_at: now, updated_at: now]],
      conflict_target: :id
    )

    :ok
  end
end
