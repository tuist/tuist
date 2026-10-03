defmodule Tuist.Repo.Migrations.CreateBazelProfileUploads do
  use Ecto.Migration

  def change do
    create table(:bazel_profile_uploads, primary_key: false) do
      add :project_id, references(:projects, on_delete: :delete_all), primary_key: true
      add :invocation_id, :text, primary_key: true
      add :compressed, :binary
      add :state, :text, null: false, default: "pending"
      add :error, :text
      timestamps(type: :timestamptz)
    end

    # The table is new and invisible to other transactions until this migration commits.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:bazel_profile_uploads, [:inserted_at])
  end
end
