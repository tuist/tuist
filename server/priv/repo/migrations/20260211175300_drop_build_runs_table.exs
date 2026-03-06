defmodule Tuist.Repo.Migrations.DropBuildRunsTable do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  def up do
    # excellent_migrations:safety-assured-for-next-line table_dropped
    drop_if_exists table(:build_runs)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DROP EXTENSION IF EXISTS timescaledb CASCADE;")
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("CREATE EXTENSION IF NOT EXISTS timescaledb;")

    create table(:build_runs, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :duration, :integer, null: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :macos_version, :string
      add :xcode_version, :string
      add :is_ci, :boolean, null: false
      add :model_identifier, :string
      add :scheme, :string
      add :inserted_at, :timestamptz, primary_key: true, null: false
      add :status, :integer
      add :git_branch, :string
      add :git_commit_sha, :string
      add :category, :integer
      add :git_ref, :string
      add :configuration, :string
      add :ci_run_id, :string
      add :ci_project_handle, :string
      add :ci_host, :string
      add :ci_provider, :integer
      add :cacheable_task_remote_hits_count, :integer, default: 0, null: false
      add :cacheable_task_local_hits_count, :integer, default: 0, null: false
      add :cacheable_tasks_count, :integer, default: 0, null: false
      add :custom_tags, {:array, :string}, default: []
      add :custom_values, :map, default: %{}
    end

    create index(:build_runs, [:project_id, :scheme])
    create index(:build_runs, [:project_id, :git_ref, :inserted_at])
    create index(:build_runs, [:project_id, :configuration, :inserted_at])
    create index(:build_runs, [:custom_tags], using: "GIN")
  end
end
