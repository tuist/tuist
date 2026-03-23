defmodule Tuist.IngestRepo.Migrations.AddShardFieldsToExistingTables do
  use Ecto.Migration

  def change do
    alter table(:test_runs) do
      add :shard_plan_id, :"Nullable(UUID)"
    end

    alter table(:test_case_runs) do
      add :shard_id, :"Nullable(UUID)"
      add :shard_index, :"Nullable(Int32)"
    end

    alter table(:test_module_runs) do
      add :shard_id, :"Nullable(UUID)"
      add :shard_index, :"Nullable(Int32)"
    end

    alter table(:test_suite_runs) do
      add :shard_id, :"Nullable(UUID)"
      add :shard_index, :"Nullable(Int32)"
    end
  end
end
