defmodule Tuist.Repo.Migrations.AddPathsToRunnerCacheVolumes do
  use Ecto.Migration

  def change do
    alter table(:runner_cache_volumes) do
      # The path spellings the saved head's `.tuist-paths` manifest records, as
      # the host reported them when publishing it; nil when unknown.
      add :paths, {:array, :string}
    end
  end
end
