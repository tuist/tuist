defmodule Tuist.Repo.Migrations.AddBuildkiteCacheVolumeIdentity do
  use Ecto.Migration

  def change do
    alter table(:runner_buildkite_jobs) do
      add :cache_volume_identity, :map
    end
  end
end
