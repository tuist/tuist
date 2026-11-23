defmodule Tuist.Repo.Migrations.AddShedAgeCountsToKuraStorageRollups do
  use Ecto.Migration

  def change do
    alter table(:kura_storage_rollups) do
      # How many of the day's capacity evictions shed content younger than
      # each growth threshold, keyed by the threshold in seconds. Null on a
      # day with no measured shed ages, and on rows rolled up before it
      # existed, which the claim sizing worker rolls up again.
      add :shed_age_counts, :map
    end
  end
end
