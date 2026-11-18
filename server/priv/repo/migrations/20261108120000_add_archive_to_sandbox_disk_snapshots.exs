defmodule Tuist.Repo.Migrations.AddArchiveToSandboxDiskSnapshots do
  use Ecto.Migration

  # A disk snapshot is also uploaded to object storage, so any node can
  # create a sandbox from it: `archive_store` and `archive_key` name the
  # object, `archive_bytes` and `archive_sha256` describe it, `archived_at`
  # is when it was completed, and `archive_upload_id` /
  # `archive_attempted_at` track an upload in flight and pace retries. An
  # archived snapshot whose node copy is gone keeps its row with no
  # `node_name`.
  def change do
    alter table(:sandbox_disk_snapshots) do
      add :archive_store, :string
      add :archive_key, :string
      add :archive_upload_id, :string
      add :archive_bytes, :bigint
      add :archive_sha256, :string
      add :archived_at, :timestamptz
      add :archive_attempted_at, :timestamptz

      # Dropping NOT NULL only changes the catalog; the table is not rewritten.
      # credo:disable-for-next-line ExcellentMigrations.CredoCheck.MigrationsSafety
      modify :node_name, :string, null: true, from: {:string, null: false}
    end
  end
end
