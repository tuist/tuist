defmodule Tuist.Repo.Migrations.AddBundles do
  use Ecto.Migration

  def change do
    create table(:bundles, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :name, :string, null: false
      add :install_size, :integer, null: false
      add :download_size, :integer
      add :app_bundle_id, :string, null: false
      add :supported_platforms, {:array, :integer}, default: []
      add :version, :string, null: false
      add :git_branch, :string
      add :git_commit_sha, :string
      add :uploaded_by_account_id, references(:accounts, on_delete: :nilify_all)
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      timestamps(type: :timestamptz)
    end

    create table(:artifacts, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :artifact_type, :string, null: false
      add :path, :string, null: false
      add :size, :integer, null: false
      add :shasum, :string, null: false
      add :bundle_id, references(:bundles, type: :uuid, on_delete: :delete_all), null: false
      add :artifact_id, references(:artifacts, type: :uuid, on_delete: :delete_all)

      timestamps(type: :timestamptz)
    end
  end
end
