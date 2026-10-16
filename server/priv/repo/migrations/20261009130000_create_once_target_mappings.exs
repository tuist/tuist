defmodule Tuist.Repo.Migrations.CreateOnceTargetMappings do
  use Ecto.Migration

  # `ActionCompleted` only names a run-local `target_execution_id`. The stable
  # target identity arrives in separate `TargetInstance` and `TargetQueued`
  # events, which these tables keep so a finished run can attribute each action
  # to its declared slot (`target_id`, `capability`, `action_index`).
  def change do
    create table(:once_target_instances, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :once_run_id, references(:once_runs, type: :uuid, on_delete: :delete_all), null: false
      add :target_instance_id, :string, null: false, size: 512
      add :target_id, :string, null: false, size: 1024
      add :configuration_digest, :string, size: 256

      timestamps(type: :timestamptz, updated_at: false)
    end

    # The table is created empty in this migration, so the index cannot lock live writes.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:once_target_instances, [:once_run_id, :target_instance_id])

    create table(:once_target_executions, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :once_run_id, references(:once_runs, type: :uuid, on_delete: :delete_all), null: false
      add :target_execution_id, :string, null: false, size: 512
      add :target_instance_id, :string, null: false, size: 512
      add :attempt, :integer, null: false, default: 0

      timestamps(type: :timestamptz, updated_at: false)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:once_target_executions, [:once_run_id, :target_execution_id])
  end
end
