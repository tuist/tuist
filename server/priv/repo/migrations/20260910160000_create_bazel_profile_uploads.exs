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

    create index(:bazel_profile_uploads, [:inserted_at])
  end
end
