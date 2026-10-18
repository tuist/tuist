defmodule Tuist.Repo.Migrations.CreateShardWorkflows do
  use Ecto.Migration

  def change do
    create table(:shard_workflows, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :reference, :text, null: false
      add :shard_count, :integer, null: false
      add :granularity, :text, null: false
      add :build_run_id, :uuid
      add :gradle_build_id, :uuid
      add :test_run_id, :uuid, null: false
      add :snapshot, :map
      add :version, :bigint, null: false, default: 0
      add :projected_version, :bigint, null: false, default: -1
      add :projection_repair_at, :timestamptz
      timestamps(type: :timestamptz)
    end

    # These tables are new, so synchronous index/constraint validation cannot
    # block reports on an existing workflow table.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:shard_workflows, [:project_id, :reference, "inserted_at DESC"])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:shard_workflows, [:test_run_id])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:shard_workflows, [:updated_at],
             where: "snapshot->>'status' = 'in_progress'",
             name: :shard_workflows_stale_in_progress
           )

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:shard_workflows, ["projection_repair_at ASC NULLS FIRST", :id],
             where: "projected_version < version",
             name: :shard_workflows_pending_projection
           )

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:shard_workflows, :positive_shard_count, check: "shard_count > 0")

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:shard_workflows, :valid_granularity,
             check: "granularity IN ('module', 'suite')"
           )

    create table(:shard_workflow_shards, primary_key: false) do
      add :workflow_id, references(:shard_workflows, type: :uuid, on_delete: :delete_all),
        primary_key: true

      add :shard_index, :integer, primary_key: true
      add :assignment, :map, null: false
      add :status, :text
      add :duration, :bigint, null: false, default: 0
      add :ran_at, :timestamptz
      add :reported_at, :timestamptz
    end

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:shard_workflow_shards, :nonnegative_shard_index, check: "shard_index >= 0")

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:shard_workflow_shards, :valid_status,
             check:
               "status IN ('processing', 'in_progress', 'success', 'failure', 'skipped', 'failed_processing')"
           )
  end
end
