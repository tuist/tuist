defmodule Tuist.Repo.Migrations.AddXcodeTargetsTable do
  use Ecto.Migration

  def change do
    create table(:xcode_targets, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :name, :string, null: false
      add :binary_cache_hash, :string
      add :binary_cache_hit, :integer
      add :selective_testing_hash, :string
      add :selective_testing_hit, :integer

      add :xcode_project_id,
          references(:xcode_projects, type: :uuid, on_delete: :delete_all),
          null: false

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:xcode_targets, [:xcode_project_id, :name])
  end
end
