defmodule Tuist.IngestRepo.Migrations.AddCasOutputNodeIdsToCacheableTasks do
  use Ecto.Migration

  def change do
    alter table(:cacheable_tasks) do
      add :cas_output_node_ids, :"Array(String)"
    end
  end
end
