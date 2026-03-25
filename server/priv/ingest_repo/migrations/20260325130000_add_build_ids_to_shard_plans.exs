defmodule Tuist.IngestRepo.Migrations.AddBuildIdsToShardPlans do
  use Ecto.Migration

  def change do
    alter table(:shard_plans) do
      add :build_run_id, :"Nullable(UUID)"
      add :gradle_build_id, :"Nullable(UUID)"
    end
  end
end
