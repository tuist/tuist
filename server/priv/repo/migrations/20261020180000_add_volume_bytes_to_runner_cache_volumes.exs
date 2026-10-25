defmodule Tuist.Repo.Migrations.AddVolumeBytesToRunnerCacheVolumes do
  use Ecto.Migration

  def change do
    alter table(:runner_cache_volumes) do
      # The size the latest publishing workflow asked for.
      add :requested_volume_bytes, :bigint
    end

    alter table(:runner_cache_volume_uses) do
      # The capacity the server chose for the use's copy.
      add :volume_bytes, :bigint
    end
  end
end
