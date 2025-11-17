defmodule Tuist.IngestRepo.Migrations.AddReadWriteDurationToCacheableTasks do
  use Ecto.Migration

  def change do
    alter table(:cacheable_tasks) do
      add :read_duration, :"Nullable(Float64)"
      add :write_duration, :"Nullable(Float64)"
    end
  end
end
