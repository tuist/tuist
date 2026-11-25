defmodule Tuist.Repo.Migrations.CreateRemoteExecutionTaskSizes do
  use Ecto.Migration

  def change do
    # What each remote action used in its last runs, keyed by the gateway's
    # size key (output paths and platform), for automatic task sizing.
    create table(:remote_execution_task_sizes, primary_key: false) do
      add :project_id, references(:projects, on_delete: :delete_all), primary_key: true
      add :key, :string, primary_key: true
      add :target_label, :text
      add :mnemonic, :string
      add :anon_peak_bytes, :bigint, null: false
      add :cores, :float, null: false
      add :p90_cores, :float, null: false
      add :wall_ms, :bigint, null: false
      add :oom_floor_gb, :integer
      add :oom_floor_until, :timestamptz
      add :runs, :integer, null: false, default: 1
      add :updated_at, :timestamptz, null: false
    end

    # Retention deletes rows unused for 14 days.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:remote_execution_task_sizes, [:updated_at])
  end
end
