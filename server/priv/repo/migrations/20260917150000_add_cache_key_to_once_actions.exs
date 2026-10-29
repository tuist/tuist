defmodule Tuist.Repo.Migrations.AddCacheKeyToOnceActions do
  use Ecto.Migration

  # Every table this migration touches (once_runs, once_actions,
  # once_cache_events, once_system_samples, once_test_suite_runs,
  # once_test_case_runs) is introduced by this same unreleased change, so
  # the first time this runs there is no populated table to lock and no
  # concurrent reader to block.
  # excellent_migrations:safety-assured-for-this-file column_added_with_default
  # excellent_migrations:safety-assured-for-this-file index_not_concurrently

  def change do
    alter table(:once_actions) do
      add :cache_key, :string, size: 128, default: "", null: false
    end

    create index(:once_actions, [:once_run_id, :cache_key])
  end
end
