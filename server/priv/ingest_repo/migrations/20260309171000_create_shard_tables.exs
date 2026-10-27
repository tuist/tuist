defmodule Tuist.IngestRepo.Migrations.CreateShardTables do
  use Ecto.Migration

  def change do
    create table(:shard_plans,
             primary_key: false,
             engine: "MergeTree",
             options: "ORDER BY (project_id, reference)"
           ) do
      add :id, :uuid, null: false
      add :reference, :string, null: false
      add :project_id, :Int64, null: false
      add :shard_count, :Int32, null: false
      add :granularity, :"LowCardinality(String)", default: "module"
      add :inserted_at, :"DateTime64(6)", default: fragment("now()")
    end

    create table(:shard_plan_modules,
             primary_key: false,
             engine: "MergeTree",
             options: "ORDER BY (project_id, shard_plan_id, shard_index, module_name)"
           ) do
      add :shard_plan_id, :uuid, null: false
      add :project_id, :Int64, null: false
      add :shard_index, :UInt16, null: false
      add :module_name, :string, null: false
      add :estimated_duration_ms, :UInt64, default: 0
      add :inserted_at, :"DateTime64(6)", default: fragment("now()")
    end

    create table(:shard_plan_test_suites,
             primary_key: false,
             engine: "MergeTree",
             options:
               "ORDER BY (project_id, shard_plan_id, shard_index, module_name, test_suite_name)"
           ) do
      add :shard_plan_id, :uuid, null: false
      add :project_id, :Int64, null: false
      add :shard_index, :UInt16, null: false
      add :module_name, :string, null: false
      add :test_suite_name, :string, null: false
      add :estimated_duration_ms, :UInt64, default: 0
      add :inserted_at, :"DateTime64(6)", default: fragment("now()")
    end

    create table(:shard_runs,
             primary_key: false,
             engine: "MergeTree",
             options: "ORDER BY (project_id, shard_plan_id, shard_index)"
           ) do
      add :shard_plan_id, :uuid, null: false
      add :project_id, :Int64, null: false
      add :test_run_id, :string, null: false
      add :shard_index, :UInt16, null: false
      add :status, :"LowCardinality(String)", null: false
      add :duration, :UInt64, default: 0
      add :ran_at, :"DateTime64(6)", default: fragment("now()")
      add :inserted_at, :"DateTime64(6)", default: fragment("now()")
    end
  end
end
