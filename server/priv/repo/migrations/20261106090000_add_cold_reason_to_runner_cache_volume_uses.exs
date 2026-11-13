defmodule Tuist.Repo.Migrations.AddColdReasonToRunnerCacheVolumeUses do
  use Ecto.Migration

  def change do
    alter table(:runner_cache_volume_uses) do
      # Why a job's host had no copy of the volume and the job started empty.
      add :cold_reason, :string
    end
  end
end
