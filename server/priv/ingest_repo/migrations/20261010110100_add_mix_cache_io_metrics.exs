defmodule Tuist.IngestRepo.Migrations.AddMixCacheIOMetrics do
  use Ecto.Migration

  def change do
    alter table(:mix_dependency_cache_events) do
      add :read_bytes, :"Nullable(UInt64)"
      add :write_bytes, :"Nullable(UInt64)"
      add :read_duration_us, :"Nullable(UInt64)"
      add :write_duration_us, :"Nullable(UInt64)"
    end
  end
end
