defmodule Tuist.IngestRepo.Migrations.AddIsCiAndBuildIdToGradleCacheEvents do
  use Ecto.Migration

  def change do
    alter table(:gradle_cache_events) do
      add :is_ci, :Bool, default: false
      add :gradle_build_id, :"Nullable(UUID)"
    end
  end
end
