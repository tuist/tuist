defmodule Tuist.IngestRepo.Migrations.AddMixCacheIOSources do
  use Ecto.Migration

  def change do
    alter table(:mix_dependency_cache_events) do
      add :read_source, :"Nullable(String)"
      add :write_source, :"Nullable(String)"
    end
  end
end
