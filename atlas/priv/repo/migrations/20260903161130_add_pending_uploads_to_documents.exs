defmodule Atlas.Repo.Migrations.AddPendingUploadsToDocuments do
  use Ecto.Migration

  def up do
    alter table(:documents) do
      modify :byte_size, :bigint, null: true
      modify :checksum_sha256, :string, null: true
      add :upload_expires_at, :utc_datetime
    end
  end

  def down do
    execute("DELETE FROM documents WHERE status = 'pending_upload'")

    alter table(:documents) do
      modify :byte_size, :bigint, null: false
      modify :checksum_sha256, :string, null: false
      remove :upload_expires_at
    end
  end
end
