defmodule Tuist.IngestRepo.Migrations.AddModuleNamesToShardPlans do
  use Ecto.Migration

  def change do
    alter table(:shard_plans) do
      add :module_names, :"Array(String)"
    end
  end
end
