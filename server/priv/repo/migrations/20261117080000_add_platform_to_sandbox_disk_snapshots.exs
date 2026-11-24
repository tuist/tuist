defmodule Tuist.Repo.Migrations.AddPlatformToSandboxDiskSnapshots do
  use Ecto.Migration

  # The OS of the sandbox a snapshot was saved from, and for macOS the bytes
  # the host measured it to hold: a macOS snapshot is a Tart VM whose overlay
  # holds only what the guest wrote, which hosts admit copies against.
  def change do
    alter table(:sandbox_disk_snapshots) do
      # PostgreSQL 11+ stores this constant default without rewriting existing rows.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :platform, :string, null: false, default: "linux"
      add :disk_bytes, :bigint
    end
  end
end
