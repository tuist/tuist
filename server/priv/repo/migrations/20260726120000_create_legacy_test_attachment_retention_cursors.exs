defmodule Tuist.Repo.Migrations.CreateLegacyTestAttachmentRetentionCursors do
  use Ecto.Migration

  def change do
    create table(:legacy_test_attachment_retention_cursors, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :artifact_type, :string, null: false
      add :completed_before, :timestamptz
      add :sweep_before, :timestamptz, null: false
      add :after_test_case_run_id, :uuid
      add :after_id, :uuid

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:legacy_test_attachment_retention_cursors, [:artifact_type])
  end
end
