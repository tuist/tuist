defmodule Tuist.Repo.Migrations.CreateOnceInvocations do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create table(:once_invocations, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, :bigint, null: false
      add :invocation_id, :string, null: false
      add :command, :string, null: false, default: "exec"
      add :argv, {:array, :string}, null: false, default: []
      add :cwd, :string
      add :action_digest, :string
      add :cache, :string, null: false, default: "miss"
      add :status, :string, null: false
      add :exit_code, :integer, null: false
      add :duration_ms, :bigint, null: false
      add :started_at, :timestamptz, null: false
      add :finished_at, :timestamptz, null: false
      add :git_branch, :string, null: false, default: ""
      add :git_commit_sha, :string, null: false, default: ""
      add :is_ci, :boolean, null: false, default: false
      add :remote_execution, :string
      add :os, :string, null: false, default: ""
      add :arch, :string, null: false, default: ""
      add :once_version, :string, null: false, default: ""
      add :workspace, :string, null: false, default: ""
      add :provider_name, :string, null: false, default: ""

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:once_invocations, :once_invocations_status_bound,
             check: "status IN ('success', 'failure')"
           )

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:once_invocations, :once_invocations_cache_bound,
             check: "cache IN ('hit', 'miss', 'bypass')"
           )

    create unique_index(
             :once_invocations,
             [:project_id, :invocation_id],
             name: :once_invocations_identity_index,
             concurrently: true
           )

    create index(:once_invocations, [:project_id, :finished_at], concurrently: true)
    create index(:once_invocations, [:inserted_at, :id], concurrently: true)
  end
end
