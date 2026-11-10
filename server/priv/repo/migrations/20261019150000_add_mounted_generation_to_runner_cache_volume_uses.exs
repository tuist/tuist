defmodule Tuist.Repo.Migrations.AddMountedGenerationToRunnerCacheVolumeUses do
  use Ecto.Migration

  def change do
    alter table(:runner_cache_volume_uses) do
      # The older generation a job mounted because its base was not on its host.
      add :mounted_generation, :bigint
    end
  end
end
