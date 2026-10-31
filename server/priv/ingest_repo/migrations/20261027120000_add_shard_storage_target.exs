defmodule Tuist.IngestRepo.Migrations.AddShardStorageTarget do
  use Ecto.Migration

  def change do
    alter table(:shard_plans) do
      add :storage_target, :"LowCardinality(String)", default: ""
    end
  end
end
