defmodule Tuist.Repo.Migrations.AddArchiveToSandboxes do
  use Ecto.Migration

  # Archived sandboxes keep their disks in object storage instead of on a
  # node: `archive_key` names the object, `archive_bytes` and
  # `archive_sha256` describe it, `archived_at` is when it was completed,
  # and `archive_upload_id` / `archive_attempted_at` track an upload in
  # flight and pace retries.
  def change do
    alter table(:sandboxes) do
      add :archive_key, :text
      add :archive_upload_id, :text
      add :archive_bytes, :bigint
      add :archive_sha256, :string
      add :archive_attempted_at, :timestamptz
      add :archived_at, :timestamptz
    end
  end
end
