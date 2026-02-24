defmodule Cache.OrphanScanCursors do
  @moduledoc false

  import Ecto.Query

  alias Cache.OrphanScanCursor
  alias Cache.Repo

  def get_cursor do
    OrphanScanCursor
    |> first()
    |> Repo.one()
  end

  def update_cursor(cursor_path) do
    upsert(%{cursor_path: cursor_path})
  end

  def reset_cursor do
    upsert(%{cursor_path: nil, last_completed_at: DateTime.utc_now()})
  end

  defp upsert(attrs) do
    cursor = get_cursor() || %OrphanScanCursor{}

    cursor
    |> OrphanScanCursor.changeset(attrs)
    |> Repo.insert_or_update!()

    :ok
  end
end
