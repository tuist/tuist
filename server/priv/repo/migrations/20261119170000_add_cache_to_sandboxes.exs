defmodule Tuist.Repo.Migrations.AddCacheToSandboxes do
  use Ecto.Migration

  def change do
    alter table(:sandboxes) do
      # The runner cache volume and saved generation a Linux sandbox's cache
      # drive was copied from when it was created; NULL without one.
      add :cache_volume_id, :uuid
      add :cache_generation, :bigint
    end
  end
end
