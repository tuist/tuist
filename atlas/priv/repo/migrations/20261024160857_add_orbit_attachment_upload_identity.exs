defmodule Atlas.Repo.Migrations.AddOrbitAttachmentUploadIdentity do
  use Ecto.Migration

  def change do
    alter table(:orbit_attachments) do
      add :client_id, :uuid, null: false
      add :payload_digest, :binary, null: false
    end

    create unique_index(:orbit_attachments, [:thread_id, :user_id, :client_id])
  end
end
