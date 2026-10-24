defmodule Atlas.Repo.Migrations.CreateOrbitAttachments do
  use Ecto.Migration

  def change do
    create table(:orbit_attachments, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :thread_id, references(:orbit_threads, type: :uuid, on_delete: :nilify_all)
      add :message_id, references(:orbit_messages, type: :uuid, on_delete: :nilify_all)
      add :user_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :filename, :string, null: false
      add :content_type, :string, null: false
      add :byte_size, :integer, null: false
      add :storage_key, :text, null: false
      add :status, :string, null: false, default: "uploading"
      add :expires_at, :timestamptz, null: false
      add :position, :integer

      timestamps(type: :timestamptz)
    end

    create index(:orbit_attachments, [:thread_id])
    create index(:orbit_attachments, [:user_id])
    create index(:orbit_attachments, [:message_id, :position])
    create index(:orbit_attachments, [:status, :expires_at])
    create unique_index(:orbit_attachments, [:storage_key])

    create constraint(:orbit_attachments, :orbit_attachments_valid_size,
             check: "byte_size > 0 AND byte_size <= 5242880"
           )

    create constraint(:orbit_attachments, :orbit_attachments_valid_status,
             check: "status IN ('uploading', 'pending', 'attached', 'deleting')"
           )
  end
end
