defmodule Tuist.Repo.Migrations.AddPhaseMsToOnceActions do
  use Ecto.Migration

  # Every table this migration touches (once_runs, once_actions,
  # once_cache_events, once_system_samples, once_test_suite_runs,
  # once_test_case_runs) is introduced by this same unreleased change, so
  # the first time this runs there is no populated table to lock and no
  # concurrent reader to block.
  # excellent_migrations:safety-assured-for-this-file column_added_with_default

  def change do
    alter table(:once_actions) do
      add :prepare_ms, :bigint, default: 0, null: false
      add :execute_ms, :bigint, default: 0, null: false
    end
  end
end
