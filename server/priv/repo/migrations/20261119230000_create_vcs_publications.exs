defmodule Tuist.Repo.Migrations.CreateVCSPublications do
  use Ecto.Migration

  def change do
    create table(:vcs_publications, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :request_id, :uuid, null: false
      add :fingerprint, :binary, null: false
      add :repository, :text, null: false
      add :operation_id, :uuid, null: false
      add :target_branch, :text, null: false
      add :base_sha, :text, null: false
      add :head_sha, :text, null: false
      add :mode, :text, null: false
      add :status, :text, null: false
      timestamps(type: :timestamptz)
    end

    # New empty table; no existing writers or rows can be blocked.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:vcs_publications, [:account_id, :request_id])
  end
end
