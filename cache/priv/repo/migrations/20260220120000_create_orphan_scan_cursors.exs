defmodule Cache.Repo.Migrations.CreateOrphanScanCursors do
  use Ecto.Migration

  def change do
    create table(:orphan_scan_cursors) do
      add :cursor_path, :text
      add :last_completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end
  end
end
