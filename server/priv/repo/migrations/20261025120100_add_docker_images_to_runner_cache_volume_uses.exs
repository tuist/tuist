defmodule Tuist.Repo.Migrations.AddDockerImagesToRunnerCacheVolumeUses do
  use Ecto.Migration

  def change do
    alter table(:runner_cache_volume_uses) do
      add :docker_images, :map
    end
  end
end
