defmodule Tuist.Repo.Migrations.AddIsCiToOnceRuns do
  use Ecto.Migration

  # `once_runs` is introduced by the same unreleased change, so there is no
  # populated table to lock and no concurrent reader to block.
  # excellent_migrations:safety-assured-for-this-file column_added_with_default
  # excellent_migrations:safety-assured-for-this-file index_not_concurrently

  def change do
    alter table(:once_runs) do
      add :is_ci, :boolean, default: false, null: false
    end

    # The Builds card on the overview filters runs by environment within a
    # project and period, which is the same access path the existing
    # project/started_at index serves.
    create index(:once_runs, [:project_id, :is_ci, :started_at])
  end
end
