defmodule Tuist.IngestRepo.Migrations.AddDescriptionToCacheableTasks do
  use Ecto.Migration

  def change do
    alter table(:cacheable_tasks) do
      add :description, :"Nullable(String)"
    end
  end
end
