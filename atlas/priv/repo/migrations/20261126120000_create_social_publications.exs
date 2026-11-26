defmodule Atlas.Repo.Migrations.CreateSocialPublications do
  use Ecto.Migration

  def change do
    # Images and videos for posts, stored under `social-media/` in the
    # documents bucket. They are uploaded to X only when their post publishes.
    create table(:social_media, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :filename, :string, null: false
      add :content_type, :string, null: false
      add :byte_size, :bigint
      add :storage_key, :string, null: false
      add :status, :string, null: false, default: "pending_upload"
      add :uploaded_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    # A post or thread for one account. `revision` grows with every edit and an
    # approval covers exactly one revision, so editing returns it to draft.
    create table(:social_publications, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :social_account_id,
          references(:social_accounts, type: :binary_id, on_delete: :nilify_all)

      add :social_post_revision_id,
          references(:social_post_revisions, type: :binary_id, on_delete: :nilify_all)

      add :items, :jsonb, null: false
      add :scheduled_at, :utc_datetime, null: false
      add :status, :string, null: false, default: "draft"
      add :revision, :integer, null: false, default: 1
      add :approved_revision, :integer
      add :approved_at, :utc_datetime
      add :approved_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :published_ids, {:array, :string}, null: false, default: []
      add :published_at, :utc_datetime
      add :last_error, :text
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:social_publications, [:status, :scheduled_at])
    create index(:social_publications, [:social_account_id])
  end
end
